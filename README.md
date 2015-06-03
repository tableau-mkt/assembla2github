# assembla2github

## Initial Setup
- NPM dependencies
  - `npm install`
- Mongo DB
  - `brew install mongodb`
  - `ln -sfv /usr/local/opt/mongodb/*.plist ~/Library/LaunchAgents`
  - `launchctl load ~/Library/LaunchAgents/homebrew.mxcl.mongodb.plist`

## Usage
- Create a .env config file (see .env-sample)
- `coffee assembla2github.coffee`
