# Backbeat

### Getting Started

1. Clone the repo:

  ```bash
  $ git clone git@github.groupondev.com:finance-engineering/backbeat.git
  ```

2. Install a Ruby version manager if necessary:
  - [chruby](https://github.com/postmodern/chruby#install)
  - [rbenv](https://github.com/sstephenson/rbenv/#installation)
  - [rvm](https://rvm.io/rvm/install/)

3. Install any of the supported Ruby versions:
  - MRI 1.9.3
  - JRuby 1.7.3

4. Install [Bundler](http://gembundler.com/) if necessary:

  ```bash
  $ gem install bundler`
  ```

5. Open up the project: `cd backbeat`

6. Install the necessary gems:

  ```bash
$ bundle install
  ```

7. Install postgres
  - [postgres](http://www.postgresql.org/download/macosx/)

8. Create backbeat role in postgres DB
  - You can use [this](http://www.postgresql.org/ftp/pgadmin3/release/v1.20.0/osx/) client to interact with DB

9. Install mongoDB

  ```bash
$ brew install mongodb
  ```

### Docker

The docker build will create a user based on the `BACKBEAT_USER_ID` and `BACKBEAT_CLIENT_URL`
environment variables set in the `backbeat_user.env` file. Change these as necessary.

Move the `backbeat_user.env.example` file into place:

```bash
$ mv backbeat_user.env.example backbeat_user.env
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

The [sample backbeat client](https://github.groupondev.com/c-kbuchanan/backbeat_sample_ruby)
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
$ sidekiq -r app.rb -q accounting_backbeat_server_v2
```

### Gitbook
[Backbeat Gitbook](https://github.groupondev.com/pages/finance-engineering/html/index.html)
=======

### Running a specific test in V2:

```bash
$ V2=true bundle exec rspec {spec_file_path}
```
