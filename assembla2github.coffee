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
prompt = require ('prompt')
ProgressBar = require ('progress')

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
      .alias('s', 'state')
      .describe('state', 'Which tickets to include (0 = closed; 1 = open; 2 = all). Defaults to open (1)')
      .describe('transform', 'Transform plugin (see readme)')
      .alias('T', 'transform')
      .describe('dry-run', 'Show what issues would have been created')
      .describe('delay', 'GitHub API call delay (in ms)')
      .alias('d', 'delay')
      .default('delay', 250)
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
prompt = Promise.promisifyAll(prompt)

mongoUrl = process.env.MONGO_URL || 'mongodb://127.0.0.1:27017/assembla2github'

db = null
collections = {}
fieldsMeta = {}

# Require transform plugin if needed
transform = require(argv.transform) if argv.transform

###
Generic Yes/No Prompt Promise
###
askYesNoConfirmation = (message) ->
  property = {
    name: 'yesno'
    message: message || 'Would you like to continue? (y/n)'
    validator: /y[es]*|n[o]?/
    warning: 'Please respond with yes or no'
    default: 'yes'
  }

  prompt.start()
  prompt.getAsync(property)
    .then (response) ->
      if response.yesno is 'yes' || response.yesno is 'y'
        return 'yes'
      else
        return 'no'


###
Purge data from MongoDB
###
purgeData = ->
  db.collectionsAsync()
    .then (data) ->
      if data.length > 0
        askYesNoConfirmation('Do you want to purge existing data?')
        .then (response) ->
          if response is 'yes'
            return data
          else
            throw new Promise.CancellationError
    .each (collection) ->
      return db.collection(collection.s.name).remove({})
    .then () ->
      console.log('data purged')
    .catch Promise.CancellationError, (e) ->
      console.log('Continuing without data purge.')

###
Import data from Assembla's dump.js file into MongoDB.
###
importDumpFile = ->
  return new Promise (resolve, reject) ->
    bar = new ProgressBar("Importing Assembla data [:bar] [:percent] [:eta seconds left]", {
      'complete': '='
      'incomplete': ' '
      'stream': process.stdout
      'total': 0
      'width': 100
    })
    fs = require('fs')
    byline = require('byline')
    eof = false

    # Count total number of lines
    countLines = new Promise (resolve, reject) ->
      countStream = byline(fs.createReadStream(argv.file, encoding: 'utf8'))
      countStream.on 'data', (line) ->
        # Initiate progress bar total
        bar.total += 1
      countStream.on 'end', -> resolve()

    countLines.then () ->
      stream = byline(fs.createReadStream(argv.file, encoding: 'utf8'))
      stream.on 'data', (line) ->
        bar.tick()
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
              # Swallow mongodb duplicate key error.
              .catch MongoDB.MongoError, (e) ->
                throw e if e.message.indexOf('duplicate key') is -1
      stream.on 'end', -> eof = true

###
Get all Assembla tickets w/ a given state

@param [Integer] state
@return [Array] tickets
###
getTickets = (state = 0) ->
  # Only retrieve tickets with a certain state
  if state == 0 or state == 1
    tickets = db.collection('tickets')
      .find({'state': state}).sort({number: -1}).toArrayAsync()
  else
    # Retrieve all tickets
    tickets = db.collection('tickets')
      .find().sort({number: -1}).toArrayAsync()

  return tickets

###
Join some values from related collections and augments the ticket object.

@param [Object] ticket object
@return [Promise] promise to be fulfilled with augmented ticket object
###
joinValues = (ticket) ->
  # Append Associations
  relationMapper = {
    0: 'parents'
    1: 'children'
    2: 'related'
    3: 'duplicates'
    6: 'subtasks'
    7: 'before'
    8: 'after'
  }
  tempAssociations = {}
  associations = db.collection('ticket_associations')
    .find({$or: [{'ticket1_id': ticket.id}, {'ticket2_id': ticket.id}]}, {'ticket1_id': 1, 'ticket2_id': 1, 'relationship': 1, '_id': 0}).toArrayAsync()
    .map (relation) ->
      relatedTicketId =
        if ticket.id is relation.ticket1_id
        then relation.ticket2_id
        else relation.ticket1_id

      db.collection('tickets')
        .find({'id': relatedTicketId}).toArrayAsync()
        .get(0)
        .then (data) ->
          key = relationMapper[relation.relationship]
          tempAssociations[key] or= {}
          tempAssociations[key][data.id] = data
    .then () ->
      return tempAssociations

  # Append Milestone
  milestone = db.collection('milestones')
    .find({'id': ticket.milestone_id}).toArrayAsync()
    .then (data) ->
      if data.length > 0
        return data[0].title

  # Append Custom Fields (e.g. audience, browser, component, deadline, focus)
  tempCustomFields = {}
  custom_fields = db.collection('workflow_property_vals')
    .find({'workflow_instance_id': ticket.id}, {'workflow_property_def_id': 1, 'value': 1, '_id': 0}).toArrayAsync()
    .map (custom_field) ->
      db.collection('workflow_property_defs').find({'id': custom_field.workflow_property_def_id}, {'title': 1, '_id': 0}).toArrayAsync()
        .map (custom_field_label) ->
          tempCustomFields[custom_field_label.title] = custom_field.value
    .then () ->
      return tempCustomFields

  # Append Status
  status = db.collection('ticket_statuses')
    .find({'id': ticket.ticket_status_id}).toArrayAsync()
    .then (data) ->
      if data.length > 0
        return data[0].title

  # Append Tags
  tags = db.collection('ticket_tags')
    .find({'ticket_id': ticket.id}, {'tag_name_id': 1, '_id': 0}).toArrayAsync()
    .then (tagIds) ->
      if tagIds.length > 0
        tagIds = _.pluck(tagIds, 'tag_name_id')
        db.collection('tag_names').find({'id': {$in: tagIds}}).toArrayAsync()
          .map (data) ->
            return data.name
    .then (results) ->
      return results

  return Promise.props(
    associations: associations,
    custom_fields: custom_fields,
    milestone: milestone,
    status: status,
    tags: tags,
    #foo: new Promise (resolve, reject) -> setTimeout(resolve, 1000)
  ).then((results) ->
    ###
      Example Issue

      id: 69995873
      number: 1
      date: '2014-01-21 18:00'
      title: 'Found a bug'
      body: 'Description of the bug']
      state: 'Open'
      status: 'New'
      priority: 'High'
      assignee: 'User Name'
      component: 'New Feature!'
      milestone: 'Sprint Ending 6/11/2015'
      plan_level: 'None'
      estimate: 'Medium'
      audience: 'Mkt General'
      browser: 'IE7'
      deadline: '2015-06-11'
      focus: 'Search'
      tags: ['tag_1', 'tag_2']
    ###

    # Mappers
    estimateMapper = {
      '1': 'None'
      '2': 'Small'
      '3': 'Medium'
      '4': 'Large'
    }
    priorityMapper = {
      '1': 'Highest'
      '2': 'High'
      '3': 'Normal'
      '4': 'Low'
      '5': 'Lowest'
    }
    stateMapper = {
      '0': 'Closed'
      '1': 'Open'
    }

    # Create Issue
    issue = {
      id: ticket.id
      number: ticket.number
      date: ticket.created_on
      title: ticket.summary
      body: ticket.description
      state: stateMapper[ticket.state]
      status: results.status || false
      priority: priorityMapper[ticket.priority]
      assignee: ticket.assigned_to_id
      component: results.custom_fields.component || false
      milestone: results.milestone || false
      plan_level: results.custom_fields.plan_level || false
      estimate: estimateMapper[ticket.estimate]
      audience: results.custom_fields.audience || false
      browser: results.custom_fields.browser || false
      deadline: results.custom_fields.deadline || false
      focus: results.custom_fields.focus || false
      tags: results.tags || []
      relatedTickets: results.associations
    }

    return issue
  )

###
Join some values from related collections and augments the ticket object.

@param [Object] ticket object
@return [Promise] promise to be fulfilled with augmented ticket object
###
updateLinks = (github, repo, bar) ->
  db.collection('assembla2github')
    .find().sort({github_issue_number: -1}).toArrayAsync()
      .each (issue) ->
        promise = []
        newBody = issue.github_issue_body

        # Retrieve all Assembla ticket numbers from body and find matching Github issue number
        re = /(?:\[GitHub:)(\d+)\]/g
        while (matches = re.exec(issue.github_issue_body)) isnt null
          assemblaId = parseInt(matches[1])
          mapping = db.collection('assembla2github')
            .find({'assembla_ticket_number': assemblaId}).toArrayAsync()

          promise.push(mapping)

        Promise.all(promise)
        .each (relatedIssues) ->
          if relatedIssues.length > 0
            relatedIssue = relatedIssues[0]
            assemblaId = relatedIssue.assembla_ticket_number
            githubId = relatedIssue.github_issue_number

            # Update Github issue number in body
            re = ///\[GitHub:#{assemblaId}\]///g
            newBody = newBody.replace(re, "##{githubId}")
        .then () ->
          # Remove remaining github link placeholders (probably referring to closed ticket)
          re = /(?:\[GitHub:)(\d+)\] /g
          newBody = newBody.replace(re, "")
        .then () ->
          if argv.dryRun
            issue.body = newBody
            console.log(issue)
          else
            # Save updated body in MongoDb
            db.collection('assembla2github').updateAsync({'_id': issue._id}, {$set: {'github_issue_body': newBody}}, {upsert: false})

            # Push updated body to GitHub
            githubIssue = github.issue(repo, issue.github_issue_number)
            githubIssue.updateAsync('body': newBody).then () -> bar.tick()

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
  bar = new ProgressBar("Exporting data to github #{argv.repo.path} [:bar] [:percent] [:eta seconds left]", {
    'complete': '='
    'incomplete': ' '
    'stream': process.stdout
    'total': 0
    'width': 100
  })
  console.log('exporting to github', argv.repo.path)
  octonode = Promise.promisifyAll(require('octonode'))
  github = octonode.client(argv['github-token'])
  repo = github.repo(argv.repo.path)
  getTickets(argv['state'])
    .then (tickets) ->
      # Initiate progress bar total (looping over tickets twice to update links)
      bar.total = tickets.length * 2
      return tickets
    .each (ticket) ->
      # Create issue object with relevant ticket information.
      joinValues(ticket)
        .then (issue) ->
          issue = transform(issue) if _.isFunction(transform)
          unless _.isObject(issue)
            console.log('skipping, no data object')
            return
          if argv.dryRun
              console.log(issue)
          else
            repo.issueAsync(
              title: issue.title
              body: issue.body
              assignee: issue.assignee
              labels: issue.labels || []
              state: issue.state
            )
            .spread (body, headers) ->
              # Save Assembla Id and Github Id mapping to MongoDb
              githubId = parseInt(body.number)
              db.collection('assembla2github').insertAsync(
                {
                  'assembla_ticket_number': issue.number
                  'github_issue_number': githubId
                  'github_issue_body': issue.body
                }
              )
            .then () ->
              bar.tick()
            .delay(argv.delay)
    .then () ->
      # Find and update links to related github issues.
      updateLinks(github, argv.repo.path, bar)

# Connect to mongodb (bluebird promises)
promise = MongoDB.MongoClient.connectAsync(mongoUrl)
  .then (_db) ->
    # Save a db and tickets collection reference
    db = _db
    tickets = db.collection('tickets')
    # Create a unique, sparse index on the number column, if it doesn't exist.
    return tickets.createIndexAsync({number: 1}, {unique: true, sparse: true})

if command is 'import'
  promise = promise.then(purgeData).then(importDumpFile)
else if command is 'export'
  promise = promise.then(exportToGithub)

promise.done ->
  console.log('All done...')
  db.close()
