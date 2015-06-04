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
argv = require('yargs').argv

# Promisify some node-callback APIs using bluebird
# @note Use `Async` suffixed methods, e.g. insertAsync, for promises.
GitHubApi = Promise.promisifyAll(GitHubApi)
MongoDB = Promise.promisifyAll(MongoDB)
MongoClient = Promise.promisifyAll(MongoDB.MongoClient)

# Check for required ENV

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
    stream = byline(fs.createReadStream(argv.i || 'dump.js', encoding: 'utf8'))
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

if argv.i or argv.import
  promise.then(importDumpFile).then(-> console.log('done importing from assembla'))
else if argv.x or argv.export
  promise.then(exportToGithub).then(-> console.log('done exporting to github'))
else
  console.log """
usage: assembla2github.coffee [-i path/to/dump.js] [-x]

options:
  -i (--import)
    import given file (assembla export format)
  -x (--export)
    export data to github
"""

promise.done ->
  console.log('exiting')
  db.close()
