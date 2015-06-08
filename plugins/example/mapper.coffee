Promise = require('bluebird')
fs = Promise.promisifyAll(require('fs'))
yaml = Promise.promisifyAll(require('js-yaml'))

fs.readFileAsync(__dirname + '/mapper.yaml')
  .then(yaml.safeLoad)
  .then((doc) ->
    console.log('mapper loaded', doc)
  )

###
Return a transformed ticket.

@note You can add a labels property as an array of strings.
###
module.exports = (ticket) ->
  ticket.labels = ['foo', 'bar']
  ticket
