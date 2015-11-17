module.exports = require('yargs')
  .usage('Usage: $0 <command> [options]')
  .command('createLabels', 'create labels in github repo', (yargs) ->
    yargs
      .describe('repo', 'GitHub repo (user/repo)')
      .demand('repo')
      .alias('r', 'repo')
      .describe('labels', 'GitHub labels to create (separated by spaces, quotes around the entire option value)')
      .alias('l', 'labels')
      .describe('transform', 'Transform plugin (see readme)')
      .alias('T', 'transform')
      .describe('github-token', 'GitHub API access token')
      .alias('t', 'github-token')
      .check((argv) ->
        repoParts = argv.repo.split('/')
        throw new Error('Check GitHub repo value') unless repoParts.length is 2
        throw new Error('labels or transform plugin option required') unless argv.labels or argv.transform
        argv['github-token'] ?= process.env.GITHUB_TOKEN
        true
      )
      .help('h').alias('h', 'help')
  )
  .command('copyLabels', 'copy labels from a given GitHub repo to other(s)', (yargs) ->
    yargs
      .describe('source', 'Source GitHub repo (user/repo)')
      .demand('s')
      .alias('s', 'source')
      .describe('target', 'Target GitHub repo(s) (user/repo). Repositories need to be separated by spaces, quotes around the entire option value.')
      .demand('d')
      .alias('d', 'target')
      .describe('github-token', 'GitHub API access token')
      .alias('t', 'github-token')
      .check((argv) ->
        repoParts = argv.source.split('/')
        throw new Error('Check source Github repo value') unless repoParts.length is 2
        throw new Error('Github repo target required') unless argv.target
        argv['github-token'] ?= process.env.GITHUB_TOKEN
        true
      )
      .help('h').alias('h', 'help')
  )
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
      .describe('comments', 'Append Assembla comments to Github body')
      .alias('c', 'comments')
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
  .example('$0 createLabels -r user/repo -l "label-one label-two label-three"')
  .example('$0 copyLabels -s user/repo -d "user/repo1 user/repo2 user/repo3"')
  .describe('verbose', 'Verbose mode')
  .alias('v', 'verbose')
  .count('verbose')
  .help('h').alias('h', 'help')
