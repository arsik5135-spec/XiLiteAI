# This file must be used with "%run bin/activate.py" from a notebook in Carnets
# you cannot run it directly

import os

homePath = os.environ['HOME']
libraryPath = os.path.join(homePath, "Library")

# deactivate:
os.environ['PYTHONPYCACHEPREFIX'] = os.path.join(libraryPath, "__pycache__")
os.environ['PYTHONUSERBASE'] = libraryPath

if (os.environ.get('_OLD_VIRTUAL_PATH') is not None):
    os.environ['PATH'] = os.environ['_OLD_VIRTUAL_PATH']
    del os.environ['_OLD_VIRTUAL_PATH']
    del os.environ['VIRTUAL_ENV']
