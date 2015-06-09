fs = require('fs')
yaml = require('js-yaml')
mapper = null
_ = require('lodash')

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

  related_tickets: {
    'parents': [],
    'children': [],
    'related': [],
    'duplicates': [],
    'subtasks': [],
    'before': [],
    'after': [],
  }
###
module.exports = (data) ->
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
      'milestones'
      'browser'
      'plan_level'
    ],
    (key) ->
      value = data[key]
      _.each([].concat(value), (labelKey) ->
        data.labels = data.labels.concat(mapper[key][labelKey] || [])
      )
  )

  # Append related ticket info to body.
  if _.any(data.related_tickets, (related) -> related.length)
    data.body += '\n\n## Related Tickets\n'
    _.each(data.related_tickets, (tickets, key) ->
      data.body += "### #{key}\n" if tickets.length
      _.each(tickets, (ticket) ->
        data.body += "- [#{ticket.title}](#{baseUrl}/#{ticket.number}) (#{ticket.number})"
      )
    )
  return data
