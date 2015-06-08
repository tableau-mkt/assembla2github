#!/usr/bin/env coffee

###
assembla2github
A migration utility for fetching Assembla tickets and creating GitHub issues.
###

require('dotenv').load()
_ = require('lodash')
Promise = require('bluebird')
MongoDB = require('mongodb')
yargs = require('yargs')
require('coffee-script/register')

# Set up yargs option parsing
yargs
  .usage('Usage: $0 <command> [options]')
  .command('import', 'import from assembla', (yargs) ->
    yargs
      .describe('file', 'assembla export file')
      .demand('file')
      .alias('f', 'file')
      .help('h').alias('h', 'help')
  )
  .command('export', 'export to github', (yargs) ->
    yargs
      .describe('repo', 'GitHub repo (user/repo)')
      .demand('repo')
      .alias('r', 'repo')
      .describe('transform', 'Transform plugin (see readme)')
      .alias('T', 'transform')
      .describe('dry-run', 'Show what issues would have been created')
      .describe('delay', 'GitHub API call delay (in ms)')
      .alias('d', 'delay')
      .default('delay', 1000)
      .describe('github-token', 'GitHub API access token')
      .alias('t', 'github-token')
      .check((argv) ->
        repoParts = argv.repo.split('/')
        throw new Error('Check GitHub repo value') unless repoParts.length is 2
        argv.repo =
          path: argv.repo
          owner: repoParts[0]
          repo: repoParts[1]
        argv['github-token'] ?= process.env.GITHUB_TOKEN
        throw new Error('GitHub token required') unless argv['github-token']
        true
      )
      .help('h').alias('h', 'help')
  )
  .demand(1)
  .example('$0 import -f dump.js')
  .example('$0 export -r user/repo')
  .describe('verbose', 'Verbose mode')
  .alias('v', 'verbose')
  .count('verbose')
  .help('h').alias('h', 'help')

# Getting argv property triggers parsing, so we ensure it comes after calling
# yargs methods.
argv = yargs.argv
command = argv._[0]
console.log(argv) #if argv.verbose

# Promisify some node-callback APIs using bluebird
# @note Use `Async` suffixed methods, e.g. insertAsync, for promises.
MongoDB = Promise.promisifyAll(MongoDB)
MongoClient = Promise.promisifyAll(MongoDB.MongoClient)
Promise.promisifyAll(MongoDB.Cursor.prototype)

mongoUrl = process.env.MONGO_URL || 'mongodb://127.0.0.1:27017/assembla2github'

db = null
collections = {}
fieldsMeta = {}

# Require transform plugin if needed
transform = require(argv.transform) if argv.transform

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

@example Fetch file contents
  repo.contentsAsync('composer.json')
    .spread (file, headers) ->
      contents = new Buffer(file.content, file.encoding).toString('utf8')
      console.log(contents)

@example Create an issue
  repo.issue({
    'title': 'Found a bug',
    'body': 'I\'m having a problem with this.',
    'assignee': 'octocat',
    'milestone': 1,
    'labels': ['Label1', 'Label2']
  })
###
exportToGithub = ->
  console.log('exporting to github', argv.repo.path)
  octonode = Promise.promisifyAll(require('octonode'))
  github = octonode.client(argv['github-token'])
  repo = github.repo(argv.repo.path)
  tickets = db.collection('tickets')
  cursor = tickets.find().sort({number: -1}).limit(2)
  cursor.toArrayAsync()
    .then (docs) ->
      for doc in docs
        doc = transform(doc) if _.isFunction(transform)
        unless _.isObject(doc)
          console.log('skipping, no data object')
          continue
        if argv.dryRun
          console.log('#%s %s [%s]', doc.number, doc.summary, (doc.labels || []).join(', '))
        else
          repo.issueAsync(
            'title': doc.summary,
            'body': doc.description,
            # 'assignee': 'octocat',
            # 'milestone': 1,
            'labels': doc.labels || []
          )
          .spread (body, headers) ->
            console.log('created issue', body)
          .delay(argv.delay)

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
