## Build Status
###MRI 1.9.3  [![Build Status](https://ci.groupondev.com/view/Finance/job/Backbeat-Master/badge/icon)](https://ci.groupondev.com/view/Finance/job/Backbeat-Master/)
###JRuby 1.7.3  [![Build Status](https://ci.groupondev.com/view/Finance/job/Backbeat-JRuby-Master/badge/icon)](https://ci.groupondev.com/view/Finance/job/Backbeat-JRuby-Master/)

## Bootstrapping your Development Environment

Start by getting a package manager for your OS if you don't have one already. We'll be using [Homebrew](http://mxcl.github.com/homebrew/) in these instructions so any where you see ```brew install something``` substitute your package manager of choice.

1. install [RVM](https://rvm.io/rvm/install/)
2. install any of the supported Ruby versions:
  * MRI 1.9.3
  * JRuby 1.7.3
3. clone the repo ```git clone git@github.groupondev.com:finance-engineering/backbeat.git```
4. open the project directory ```cd backbeat```
5. install bundler ```gem install bundler```
6. install all the gems ```bundle install```
7. install mongo ```brew install mongo```

That should do it! Now you can:

Start a Console:
```
bin/console
```

Start the Server:
```
unicorn -c config/unicorn.conf.rb&
script/delayed_job_backbeat start /tmp/backbeat_delayedjob_pid_file
```

###Things You Should Be Doing
- look for cruft, bad method/variable names, anything excessivley confusing or complicated, etc..
- document as you go
- blog as you go - take enough notes that you could right a real blog post later
- story pain-points/needs/wants/dreams/anything that warrants discussion 
- tag anything that seems crufty with a TODO in addition to creating a story
- when versioning:
  - Use sane version numbering
  - tag versions bumps in git
  - update change_log.md on version bump

###Open Questions###
-Contract for client compatibility with server? (see versioning)
