###
assembla2github
A migration utility for fetching Assembla tickets and creating GitHub issues.
###

require('dotenv').load()
_ = require('lodash')
rest = require('restling')
util = require('util')
Promise = require('bluebird')
MongoDB = require('mongodb')

# Promisify the MongoDB API and MongoClient using bluebird
# @note Use `Async` suffixed methods, e.g. insertAsync, for promises.
MongoDB = Promise.promisifyAll(MongoDB)
MongoClient = Promise.promisifyAll(MongoDB.MongoClient)

url = 'mongodb://127.0.0.1:27017/assembla2github'
assemblaConfig = {
  api: 'https://api.assembla.com'
  key: process.env.ASSEMBLA_KEY
  secret: process.env.ASSEMBLA_SECRET
  space: process.env.ASSEMBLA_SPACE
  delay: 200
}
# Check for required config
unless _.every(['key', 'secret', 'space'], (key) -> _.has(assemblaConfig, key))
  throw new Error('Missing one or more required environment variables (ASSEMBLA_KEY, ASSEMBLA_SECRET, ASSEMBLA_SPACE)')

db = null
tickets = null

###
While loop using promises.
Call an action until a condition is satisfied.

@example Basic usage
  promiseWhile (-> !done), (-> doSomething())

@param {Function} condition  the condition to check
@param {Function} action  the action to call
###
promiseWhile = (condition, action) ->
  new Promise((resolve, reject) ->
    next = ->
      return resolve() unless condition()
      Promise.resolve(action()).then(next).catch (e) -> reject e

    process.nextTick next
)

###
Fetch a page of tickets from Assembla.

@example Basic usage
  fetchTickets(0)
    .then((result) -> console.log(result))
    .error(-> console.log('fail'))

@param {Number} page  the page to fetch (0 index)
###
fetchTickets = (page) ->
  console.log('fetching assembla tickets page', page)

  headers =
    'X-Api-Key': assemblaConfig.key
    'X-Api-Secret': assemblaConfig.secret
  query =
    report: '0'
    per_page: '100'
    page: page || 0
    sort_by: 'number'
    sort_order: 'desc'
  options =
    query: query
    headers: headers

  return rest.get("#{assemblaConfig.api}/v1/spaces/#{assemblaConfig.space}/tickets.json", options)

# Connect to mongodb (bluebird promises)
MongoDB.MongoClient.connectAsync(url)
  .then (_db) ->
    # Save a db and tickets collection reference
    db = _db
    tickets = db.collection('tickets')
    # Create a unique, sparse index on the number column, if it doesn't exist.
    return tickets.createIndexAsync({number: 1}, {unique: true, sparse: true})
  .then ->
    # Fetch all tickets using our promiseWhile helper.
    hasData = true
    page = 0
    promiseWhile(
      -> hasData,
      ->
        fetchTickets(page)
          .then (result) ->
            if _.isArray(result.data)
              page++
              return tickets.insertAsync(result.data)
            else
              # Assembla returns an empty response when the page doesn't exist.
              hasData = false
              console.log('no data')
              return
          # Swallow mongodb duplicate key error.
          .catch MongoDB.MongoError, (e) ->
            throw e if e.message.indexOf('duplicate key') is -1
          .error (e) -> console.log(e)
          # Short delay between API calls.
          .delay(assemblaConfig.delay)
    )
  .done ->
    console.log('done fetching from assembla')
    db.close()
