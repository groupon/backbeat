# Backbeat Server

This is the server application for Backbeat, the open-source workflow service by Groupon. For more information on what Backbeat is, and documentation for using Backbeat, see [the wiki](https://github.groupondev.com/backbeat/backbeat_server/wiki).

### Setting up the Server Application

1. Clone the repo:

  ```bash
  $ git clone git@github.groupondev.com:backbeat/backbeat_server.git
  ```

2. Install a Ruby version manager if necessary:
  - [chruby](https://github.com/postmodern/chruby#install)
  - [rbenv](https://github.com/sstephenson/rbenv/#installation)
  - [rvm](https://rvm.io/rvm/install/)

3. Install any of the supported Ruby versions:
  - JRuby 1.7.3 - 1.7.20
  - MRI 1.9.3 - 2.1.6

4. Install [Bundler](http://gembundler.com/) if necessary:

  ```bash
  $ gem install bundler
  ```

5. Open up the project:

  ```bash
  $ cd backbeat
  ```

6. Install the necessary gems:

  ```bash
  $ bundle install
  ```

7. Install Postgres or [use an existing Postgres db](https://github.groupondev.com/backbeat/backbeat_server/wiki/Customize-Backbeat#postgres)
 	- We recommend postgresql-9.4 but Backbeat currently supports any postgres version that allows the uuid-ossp extension
	- Install on Mac OS

      ```bash
      $ brew install postgres
      ```
    - [Install on Linux](http://www.postgresql.org/download/linux/)

8. Create backbeat role in postgres DB with your postgres user (postgres in this example)

  ```bash
  $ sudo su postgres -c "psql -c \"CREATE ROLE backbeat with SUPERUSER LOGIN PASSWORD 'b4ckb347'\";"
  ```
  -  Note you can change your db configs to what ever you'd like in config/database.yml. The above command allows for the default values in the .yml

9. Run the database migrations using the following

  ```bash
  $ bundle exec rake db:migrate
  ```
10. Open backbeat server console and you have access to the db

  ```bash
  $ bundle exec rake console
  ```
  
  ```ruby
  Workflow.last # should return nil
  ```
11. Install Redis or [use an existing Redis instance](https://github.groupondev.com/backbeat/backbeat_server/wiki/Customize-Backbeat#redis)
  - Redis is used for processing of asynchronous and scheduled jobs with Sidekiq
  - Install on Mac OS

  	```bash
    $ brew install redis
    ```
  - [Install on Linux](http://redis.io/topics/quickstart)
  - Start Redis

    ```bash
    $ redis-server
    ```
12. Start Web Server and Workers
  - For testing you can run these as daemons or in different terminal windows 
  - For production you will want to use some sort of monitoring on these processes. We provide an option using God as explained [here]().

  ```bash
  $ bundle exec rackup # you can now hit backbeat from http://localhost:9292 or expose the port externally
  ```

  ```bash
  $ bin/sidekiq # workers can now pick up async jobs
  ```

### Docker

The docker build will create a user based on the `BACKBEAT_USER_ID` and `BACKBEAT_CLIENT_URL`
environment variables set in the `backbeat_user.env` file. Change these as necessary.

Move the `backbeat_user.env.example` file into place:

```bash
$ mv docker/backbeat_user.env.example docker/backbeat_user.env
```

Set the docker-compose file environment variable:

```bash
$ export COMPOSE_FILE=docker/docker-compose.local.yml
```

```bash
$ docker-compose build
$ docker-compose up
```

Run a console:

```bash
$ bin/docker_console
```

### Sample App

The [sample backbeat client](https://github.groupondev.com/backbeat/backbeat_sample_ruby)
is already configured to work with a local dockerized backbeat.

### Commands

Running the tests:

```bash
$ RACK_ENV=test rake db:create db:migrate
$ rspec
```

Run the migrations:

```bash
$ rake db:create db:migrate
```

Open a console:

```bash
$ rake console
```

Start the server:

```bash
$ rackup
```

Start the sidekiq workers:

```bash
$ bin/sidekiq
```
