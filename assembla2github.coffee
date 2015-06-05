#!/usr/bin/env coffee

###
assembla2github
A migration utility for fetching Assembla tickets and creating GitHub issues.
###

require('dotenv').load()
_ = require('lodash')
util = require('util')
Promise = require('bluebird')
MongoDB = require('mongodb')
GitHubApi = require('github')
yargs = require('yargs')

# Set up yargs option parsing
yargs
  .usage('Usage: $0 <command> [options]')
  .command('import', 'import from assembla', (yargs) ->
    argv = yargs
      .describe('file', 'assembla export file')
      .demand('file')
      .alias('f', 'file')
      .argv
  )
  .command('export', 'export to github', (yargs) ->
    argv = yargs
      .describe('repo', 'GitHub repo (user/repo)')
      .demand('repo')
      .alias('r', 'repo')
      .describe('github-token', 'GitHub API access token')
      .alias('t', 'github-token')
      .check((argv) ->
        argv['github-token'] ?= process.env.GITHUB_TOKEN
        throw new Error('GitHub token required') unless argv['github-token']
        true
      )
      .argv
  )
  .demand(1)
  .example('$0 import -f dump.js')
  .example('$0 export -r user/repo')
  .help('h')
  .alias('h', 'help')

# Getting argv property triggers parsing, so we ensure it comes after calling
# yargs methods.
argv = yargs.argv
command = argv._[0]

# Promisify some node-callback APIs using bluebird
# @note Use `Async` suffixed methods, e.g. insertAsync, for promises.
GitHubApi = Promise.promisifyAll(GitHubApi)
MongoDB = Promise.promisifyAll(MongoDB)
MongoClient = Promise.promisifyAll(MongoDB.MongoClient)

mongoUrl = process.env.MONGO_URL || 'mongodb://127.0.0.1:27017/assembla2github'

db = null
collections = {}
fieldsMeta = {}

###
Import data from Assembla's dump.js file into MongoDB.
###
importDumpFile = ->
  console.log('importing assembla data from dump.js')
  return new Promise (resolve, reject) ->
    fs = require('fs')
    byline = require('byline')
    eof = false
    stream = byline(fs.createReadStream(argv.file, encoding: 'utf8'))
    stream.on 'data', (line) ->
      matches = line.match(/^([\w]+)(:fields)?, (.+)$/)
      if matches
        fields = Boolean(matches[2])
        name = matches[1]
        data = JSON.parse(matches[3])
        fieldsMeta[name] = data if fields
        collections[name] = db.collection(name) unless collections[name]
        unless fields
          # Convert line to Object.
          doc = _.zipObject(fieldsMeta[name], data)
          # Insert into mongo collection.
          collections[name].insertAsync(doc)
            .then ->
              resolve() if eof
              process.stdout.write('.')
            # Swallow mongodb duplicate key error.
            .catch MongoDB.MongoError, (e) ->
              throw e if e.message.indexOf('duplicate key') is -1
    stream.on 'end', -> eof = true

###
Export data to GitHub
###
exportToGithub = ->
  console.log('exporting to github')

# Connect to mongodb (bluebird promises)
promise = MongoDB.MongoClient.connectAsync(mongoUrl)
  .then (_db) ->
    # Save a db and tickets collection reference
    db = _db
    tickets = db.collection('tickets')
    # Create a unique, sparse index on the number column, if it doesn't exist.
    return tickets.createIndexAsync({number: 1}, {unique: true, sparse: true})

if command is 'import'
  promise = promise.then(importDumpFile).then(-> console.log('done importing from assembla'))
else if command is 'export'
  promise = promise.then(exportToGithub).then(-> console.log('done exporting to github'))

promise.done ->
  console.log('exiting')
  db.close()
