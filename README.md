# assembla2github

A tool to copy Assembla tickets into GitHub

## Initial Setup
- NPM dependencies
  - `npm install`
- Mongo DB
  - `brew install mongodb`
  - `ln -sfv /usr/local/opt/mongodb/*.plist ~/Library/LaunchAgents`
  - `launchctl load ~/Library/LaunchAgents/homebrew.mxcl.mongodb.plist`

## Usage
- Create a .env config file (see .env-sample)
- Run `./assembla2github.coffee`
