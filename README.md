# assembla2github

A tool to copy Assembla tickets into GitHub.

## Initial Setup
- NPM dependencies
  - `npm install`
- Mongo DB
  - `brew install mongodb`
  - `ln -sfv /usr/local/opt/mongodb/*.plist ~/Library/LaunchAgents`
  - `launchctl load ~/Library/LaunchAgents/homebrew.mxcl.mongodb.plist`

## Usage
- Create a .env config file (see .env-sample)
- Run `./assembla2github.coffee --help` for usage and examples.

```
./assembla2github.coffee --help
Usage: coffee assembla2github.coffee <command> [options]

Commands:
  labels  create labels in github repo
  import  import from assembla
  export  export to github

Options:
  -h, --help     Show help                                             [boolean]
  -v, --verbose  Verbose mode                                            [count]

Examples:
  coffee assembla2github.coffee import -f
  dump.js
  coffee assembla2github.coffee export -r
  user/repo
  coffee assembla2github.coffee labels -r
  user/repo -l "label-one label-two label-
  three"
```
