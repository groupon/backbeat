FROM jruby:1.7

MAINTAINER opensource@groupon.com

RUN apt-get -q update
RUN apt-get -q -q -y install git

RUN mkdir /app
WORKDIR /app

ADD Gemfile /app/
ADD Gemfile.lock /app/
RUN bundle install --without development torquebox

ADD . /app
