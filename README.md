# Backbeat

### Getting Started

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

7. Install [postgres](http://www.postgresql.org/download/macosx/)

  ```bash
  $ brew install postgres
  ```

8. Create backbeat role in postgres DB

  ```bash
  $ psql -c "CREATE ROLE backbeat"
  ```
  - You can also use [this](http://www.postgresql.org/ftp/pgadmin3/release/v1.20.0/osx/) client to interact with DB

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
$ bin/console
```

Start the server:

```bash
$ rackup
```

Start the sidekiq workers:

```bash
$ bin/sidekiq
```

### Gitbook

[Backbeat Gitbook](https://github.groupondev.com/pages/finance-engineering/html/index.html)
