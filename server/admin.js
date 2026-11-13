const fs = require('node:fs');
const path = require('node:path');

const accountsPath = process.env.ACCOUNTS_PATH || path.join(__dirname, 'accounts.json');
const args = process.argv.slice(2);
const [command, action, ...nameParts] = args[0] === 'premium'
    ? [args[0], args[1], ...args.slice(2)]
    : ['premium', args[0], ...args.slice(1)];
const name = nameParts.join(' ').trim().replace(/\s+/g, ' ');

function usage() {
    console.error('Usage: npm run premium -- give <accountName>');
    console.error('       npm run premium -- remove <accountName>');
    console.error('       npm run premium -- accounts');
    process.exit(2);
}

function normalize(value) {
    return value.toLocaleLowerCase();
}

if (command !== 'premium' || !['give', 'remove', 'accounts'].includes(action)) usage();

let database;
try {
    database = JSON.parse(fs.readFileSync(accountsPath, 'utf8'));
} catch (error) {
    console.error(`Cannot read ${accountsPath}: ${error.message}`);
    process.exit(1);
}

if (!Array.isArray(database.accounts)) {
    console.error('accounts.json has an invalid format (expected an accounts array).');
    process.exit(1);
}

if (action === 'accounts') {
    for (const account of database.accounts) {
        console.log(`${account.accountName}\t${account.isPremium ? 'premium' : 'free'}`);
    }
    process.exit(0);
}

if (!name) usage();
const account = database.accounts.find(item => normalize(item.accountName) === normalize(name));
if (!account) {
    console.error(`Account not found: ${name}`);
    process.exit(1);
}

account.isPremium = action === 'give';
const temporaryPath = `${accountsPath}.tmp`;
try {
    fs.writeFileSync(temporaryPath, `${JSON.stringify(database, null, 2)}\n`, { mode: 0o600 });
    fs.renameSync(temporaryPath, accountsPath);
    console.log(`${account.accountName}: isPremium=${account.isPremium}`);
} catch (error) {
    try { fs.unlinkSync(temporaryPath); } catch {}
    console.error(`Cannot update ${accountsPath}: ${error.message}`);
    process.exit(1);
}
