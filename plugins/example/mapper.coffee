fs = require('fs')
yaml = require('js-yaml')
mapper = null
secret = null
_ = require('lodash')

try
  mapper = yaml.safeLoad(fs.readFileSync(__dirname + '/mapper.yaml', 'utf8'))
  # Convert mapper keys to lowercase for case-insensitive lookups.
  _.each(mapper, (value, key) ->
    if _.isObject value
      mapper[key] = _.mapKeys(value, (value, key) -> key.toLowerCase())
  )
  console.log('mapper loaded', mapper)
  secret = yaml.safeLoad(fs.readFileSync(__dirname + '/secret.yaml', 'utf8'))
  console.log('private mapper loaded', secret)
catch e
  console.log(e)


###
Transform the data object before exporting to GitHub.

@param [Object] data to export
@return [Object] transformed data

@note You can add a labels property as an array of strings.

@note ticket example object
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

  relatedTickets: {
    'parents': [],
    'children': [],
    'related': [],
    'duplicates': [],
    'subtasks': [],
    'before': [],
    'after': [],
  }
###
module.exports.transform = (data) ->
  baseUrl = 'https://www.assembla.com/spaces/upgrade/tickets'

  # Map values into an array of labels.
  data.labels = []
  _.each([
      'status'
      'priority'
      'component'
      'estimate'
      'audience'
      'focus'
      'tags'
      'milestone'
      'browser'
      'plan_level'
    ],
    (key) ->
      value = String(data[key]).toLowerCase()
      _.each([].concat(value), (labelKey) ->
        data.labels = data.labels.concat(mapper[key][String(labelKey).toLowerCase()] || [])
      )
  )

  # Replace some basic textile with markdown equivalent.
  data.body = data.body.replace(/^###/gm, '    *')
  data.body = data.body.replace(/^##/gm, '  *')
  data.body = data.body.replace(/^#/gm, '1.')

  data.body = data.body.replace(/^\*\*\*/gm, '    *')
  data.body = data.body.replace(/^\*\*/gm, '  *')

  data.body = data.body.replace(/h1\./g, '#')
  data.body = data.body.replace(/h2\./g, '##')
  data.body = data.body.replace(/h3\./g, '###')
  data.body = data.body.replace(/h4\./g, '####')
  data.body = data.body.replace(/h5\./g, '#####')
  data.body = data.body.replace(/h6\./g, '######')

  # Append Assembla link.
  data.body += "\n\n>__&lt;META&gt;__"
  data.body += "\n>Original Ticket: [Assembla](https://www.assembla.com/spaces/upgrade/tickets/#{data.number})"

  # Append related ticket info to body.
  if _.keys(data.relatedTickets).length
    _.each(data.relatedTickets, (tickets, key) ->
      key = _.capitalize(key)
      data.body += "\n#{key}:" if _.keys(tickets).length
      _.each(tickets, (ticket) ->
        data.body += "\n- #{ticket.summary} ([Assembla](#{baseUrl}/#{ticket.number}), [GitHub](#{ticket.number}))"
      )
    )

  # Map user ID to GitHub username.
  try
    data.assignee = secret.assembla_users[data.assignee]
    data.assignee = secret.github_users[data.assignee]
  catch error
    delete data.assignee

  return data

module.exports.createLabels = ->
  _.chain(mapper)
    .reduce((labels, item) ->
      if _.isObject(item)
        labels.concat(_.flatten(_.values(item)))
      else
        labels
    , [])
    .uniq()
    .map((label) -> {name: label})
    .value()
