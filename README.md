### Getting Started
This guide should get you from zero to running Backbeat locally in 301 seconds flat or your money back!

__Step 1__: Clone the repo: ```git clone
git@github.groupondev.com:finance-engineering/backbeat.git```  
__Step 2__: Install [chruby](https://github.com/postmodern/chruby#install)
or [rbenv](https://github.com/sstephenson/rbenv/#installation) or
[rvm](https://rvm.io/rvm/install/)  
__Step 3__: Install any of the supported Ruby versions:
 - MRI 1.9.3
 - JRuby 1.7.3

__Step 4__: Open up the Project! `cd backbeat`  
__Step 5__: Install [Bundler](http://gembundler.com/) `gem install bundler`  
__Step 6__: Install the gems `bundle install`  
__Step 7__: Install [MongoDB](http://www.mongodb.org/) `brew install mongo`  
__Step 8__: :money_with_wings:  PROFIT :money_with_wings:   					

__What are you going to do next? You could...__  
Open a console:  
```
bin/console
```
Start the server:  
```
bin/server
script/delayed_job_backbeat start /tmp/backbeat_delayedjob_pid_file
```
Immediately regret this decision:
```
cd ..
rm -rf backbeat
```
