Promise = require('bluebird')
fs = Promise.promisifyAll(require('fs'))
yaml = Promise.promisifyAll(require('js-yaml'))

fs.readFileAsync(__dirname + '/mapper.yaml')
  .then(yaml.safeLoad)
  .then((doc) ->
    console.log('mapper loaded', doc)
  )

module.exports =
  ###
  Return an array of labels given a ticket
  ###
  labels: (ticket) ->
    ['foo', 'bar']
