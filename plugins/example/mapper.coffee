fs = require('fs')
yaml = require('js-yaml')
mapper = null

try
  doc = yaml.safeLoad(fs.readFileSync(__dirname + '/mapper.yaml', 'utf8'))
  console.log('mapper loaded', doc)
  mapper = doc
catch e
  console.log(e)

###
Transform the data object before exporting to GitHub.

@param [Object] data to export
@return [Object] transformed data

@note You can add a labels property as an array of strings.
###
module.exports = (data) ->
  data.labels = ['foo', 'bar']
  return data
