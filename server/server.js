const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const readline = require('node:readline');

if (process.argv[2] === 'premium') {
    const { spawnSync } = require('node:child_process');
    const result = spawnSync(process.execPath, [path.join(__dirname, 'admin.js'), ...process.argv.slice(2)], { stdio: 'inherit' });
    process.exit(result.status ?? 1);
}

const PORT = Number(process.env.PORT || 3000);
const ACCOUNTS_PATH = process.env.ACCOUNTS_PATH || path.join(__dirname, 'accounts.json');
const SESSION_MS = 7 * 24 * 60 * 60 * 1000;
const PIN_PATTERN = /^\d{4,12}$/;
let accounts = loadAccounts();
const loginAttempts = new Map();
let accountsModifiedAt = getAccountsModifiedAt();

function getAccountsModifiedAt() {
    try { return fs.statSync(ACCOUNTS_PATH).mtimeMs; }
    catch { return 0; }
}

function refreshAccountsFromDisk() {
    const modifiedAt = getAccountsModifiedAt();
    if (modifiedAt && modifiedAt !== accountsModifiedAt) {
        accounts = loadAccounts();
        accountsModifiedAt = modifiedAt;
    }
}

function loadAccounts() {
    try {
        const content = fs.readFileSync(ACCOUNTS_PATH, 'utf8');
        const parsed = JSON.parse(content);
        return Array.isArray(parsed.accounts) ? parsed.accounts : [];
    } catch (error) {
        if (error.code !== 'ENOENT') console.error('Could not read accounts.json:', error.message);
        return [];
    }
}

function saveAccounts() {
    const temporaryPath = `${ACCOUNTS_PATH}.tmp`;
    fs.writeFileSync(temporaryPath, `${JSON.stringify({ accounts }, null, 2)}\n`, { mode: 0o600 });
    fs.renameSync(temporaryPath, ACCOUNTS_PATH);
    accountsModifiedAt = getAccountsModifiedAt();
}

function send(response, statusCode, value) {
    response.writeHead(statusCode, {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff'
    });
    response.end(JSON.stringify(value));
}

async function readJSON(request) {
    let body = '';
    for await (const chunk of request) {
        body += chunk;
        if (body.length > 32 * 1024) throw new Error('Request body too large.');
    }
    return body ? JSON.parse(body) : {};
}

function normalizeName(name) {
    return typeof name === 'string' ? name.trim().replace(/\s+/g, ' ') : '';
}

function findAccount(name) {
    const normalized = normalizeName(name).toLocaleLowerCase();
    return accounts.find(account => account.accountName.toLocaleLowerCase() === normalized);
}

function derivePin(pin, salt) {
    return crypto.scryptSync(pin, salt, 64).toString('hex');
}

function hashToken(token) {
    return crypto.createHash('sha256').update(token).digest('hex');
}

function issueSession(account) {
    const token = crypto.randomBytes(32).toString('base64url');
    account.sessionTokenHash = hashToken(token);
    account.sessionExpiresAt = Date.now() + SESSION_MS;
    saveAccounts();
    return { token, expiresAt: account.sessionExpiresAt };
}

function bearerToken(request) {
    const value = request.headers.authorization || '';
    return value.startsWith('Bearer ') ? value.slice(7) : '';
}

function accountForToken(request) {
    const token = bearerToken(request);
    if (!token) return null;
    const digest = hashToken(token);
    const account = accounts.find(item => item.sessionTokenHash && crypto.timingSafeEqual(Buffer.from(item.sessionTokenHash, 'hex'), Buffer.from(digest, 'hex')));
    if (!account || account.sessionExpiresAt <= Date.now()) return null;
    return account;
}

function publicAccount(account) {
    return {
        accountName: account.accountName,
        isPremium: account.isPremium === true,
        sessionExpiresAt: account.sessionExpiresAt
    };
}

const server = http.createServer(async (request, response) => {
    refreshAccountsFromDisk();
    const url = new URL(request.url, `http://${request.headers.host || 'localhost'}`);
    try {
        if (request.method === 'GET' && url.pathname === '/health') return send(response, 200, { ok: true });

        if (request.method === 'POST' && url.pathname === '/auth/register') {
            const body = await readJSON(request);
            const accountName = normalizeName(body.accountName);
            const pin = String(body.pin || '');
            if (accountName.length < 2 || accountName.length > 32 || !/^[\p{L}\p{N}_. -]+$/u.test(accountName)) {
                return send(response, 400, { error: 'Имя: 2–32 символа, буквы, цифры, пробел, точка, дефис или _.' });
            }
            if (!PIN_PATTERN.test(pin)) return send(response, 400, { error: 'PIN-код должен содержать от 4 до 12 цифр.' });
            if (findAccount(accountName)) return send(response, 409, { error: 'Это имя уже занято.' });
            const pinSalt = crypto.randomBytes(16).toString('hex');
            const account = { accountName, pinSalt, pinHash: derivePin(pin, pinSalt), isPremium: false, createdAt: Date.now() };
            accounts.push(account);
            const session = issueSession(account);
            return send(response, 201, { ...publicAccount(account), token: session.token });
        }

        if (request.method === 'POST' && url.pathname === '/auth/login') {
            const body = await readJSON(request);
            const normalizedName = normalizeName(body.accountName).toLocaleLowerCase();
            const attempt = loginAttempts.get(normalizedName) || { count: 0, blockedUntil: 0 };
            if (attempt.blockedUntil > Date.now()) return send(response, 429, { error: 'Слишком много попыток. Повторите позже.' });
            const account = findAccount(body.accountName);
            const pin = String(body.pin || '');
            const validPin = account && PIN_PATTERN.test(pin) && crypto.timingSafeEqual(
                Buffer.from(account.pinHash, 'hex'),
                Buffer.from(derivePin(pin, account.pinSalt), 'hex')
            );
            if (!validPin) {
                attempt.count += 1;
                if (attempt.count >= 5) {
                    attempt.count = 0;
                    attempt.blockedUntil = Date.now() + 60_000;
                }
                loginAttempts.set(normalizedName, attempt);
                return send(response, 401, { error: 'Неверное имя или PIN-код.' });
            }
            loginAttempts.delete(normalizedName);
            const session = issueSession(account);
            return send(response, 200, { ...publicAccount(account), token: session.token });
        }

        if (request.method === 'POST' && url.pathname === '/auth/logout') {
            const account = accountForToken(request);
            if (account) {
                delete account.sessionTokenHash;
                delete account.sessionExpiresAt;
                saveAccounts();
            }
            return send(response, 200, { ok: true });
        }

        const account = accountForToken(request);
        if (!account) return send(response, 401, { error: 'Сессия истекла. Войдите снова.' });

        if (request.method === 'GET' && url.pathname === '/account') return send(response, 200, publicAccount(account));

        if (request.method === 'PATCH' && url.pathname === '/account') {
            const body = await readJSON(request);
            const accountName = normalizeName(body.accountName);
            if (accountName.length < 2 || accountName.length > 32 || !/^[\p{L}\p{N}_. -]+$/u.test(accountName)) {
                return send(response, 400, { error: 'Имя должно содержать от 2 до 32 допустимых символов.' });
            }
            const owner = findAccount(accountName);
            if (owner && owner !== account) return send(response, 409, { error: 'Это имя уже занято.' });
            account.accountName = accountName;
            saveAccounts();
            return send(response, 200, publicAccount(account));
        }

        if (request.method === 'PUT' && url.pathname === '/account/pin') {
            const body = await readJSON(request);
            const currentPin = String(body.currentPin || '');
            const newPin = String(body.newPin || '');
            if (!PIN_PATTERN.test(currentPin) || !PIN_PATTERN.test(newPin)) return send(response, 400, { error: 'PIN-код должен содержать от 4 до 12 цифр.' });
            const expected = Buffer.from(account.pinHash, 'hex');
            const supplied = Buffer.from(derivePin(currentPin, account.pinSalt), 'hex');
            if (!crypto.timingSafeEqual(expected, supplied)) return send(response, 401, { error: 'Текущий PIN-код указан неверно.' });
            account.pinSalt = crypto.randomBytes(16).toString('hex');
            account.pinHash = derivePin(newPin, account.pinSalt);
            saveAccounts();
            return send(response, 200, { ok: true });
        }

        return send(response, 404, { error: 'Маршрут не найден.' });
    } catch (error) {
        console.error(error);
        return send(response, 400, { error: error.message || 'Некорректный запрос.' });
    }
});

server.listen(PORT, '0.0.0.0', () => {
    console.log(`Xi Lite account server listening on http://0.0.0.0:${PORT}`);
    console.log(`Accounts: ${ACCOUNTS_PATH}`);
    console.log('Admin commands: premium give <name> | premium remove <name> | accounts | exit');
});

const terminal = readline.createInterface({ input: process.stdin, output: process.stdout, prompt: 'xi-admin> ' });
terminal.prompt();
terminal.on('line', line => {
    const [command, action, ...nameParts] = line.trim().split(/\s+/);
    const name = nameParts.join(' ');
    if (command === 'exit' || command === 'quit') {
        server.close(() => process.exit(0));
        return;
    }
    if (command === 'accounts') {
        for (const account of accounts) console.log(`${account.accountName}\t${account.isPremium ? 'premium' : 'free'}`);
    } else if (command === 'premium' && ['give', 'remove'].includes(action) && name) {
        const account = findAccount(name);
        if (!account) console.log(`Account not found: ${name}`);
        else {
            account.isPremium = action === 'give';
            saveAccounts();
            console.log(`${account.accountName}: isPremium=${account.isPremium}`);
        }
    } else {
        console.log('Commands: premium give <name> | premium remove <name> | accounts | exit');
    }
    terminal.prompt();
});
