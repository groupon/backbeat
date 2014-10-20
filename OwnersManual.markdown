Contents
--------

[Application Information](#Application_Information)

-   [Architecture](#Architecture)
-   [Starting the Application](#Starting_the_Application)
-   [Data store](#Data_store)

[Standard Operating Procedures](#Standard_Operating_Procedures)

[Deployment](#Deployment)

[Adding Capacity](#Adding_Capacity)

[Troubleshooting](#Troubleshooting)

* * * * *

<a name="Application_Information"></a>Backbeat
=======================

Backbeat is a workflow service (a la Amazon Simple Workflow).  It's used by Accounting Service and VAT Invoicing service (And maybe other things). Backbeat solves some of the things required by most of the services such as - serialization, auto-retry, error recording and reporting, parallelism.  

Written in Ruby, uses Mongo (tokumx) for its database, Sidekiq for async workers and Delayed Job for scheduled tasks (DJ runs on accounting-worker1.snc1).

<a name="Architecture"></a>Architecture
=======================
```
Hosts		: accounting-worker{1-3}.snc1 (jruby with grape inside of JBoss)
Database	: accounting-tokumx{1-3}.snc1 (tokumx, a mongo replacement)
Async Jobs	: general-redis-vip.snc1
Load balancer	: accounting-backbeat-vip.snc1
```

![Backbeat Architecture](/backbeat_architecture.png "Backbeat Architecture")

<a name="Starting_the_Application"></a>Starting the Application
=======================

1. Clone the [Spinderella](https://github.groupondev.com/finance-engineering/spinderella) repo
2. start jboss (this should start the web and sidekiq workers)
```
bundle exec cap torquebox:backbeat:production jboss:start
```
3. start the delayed job worker
```
bundle exec cap torquebox:backbeat:production workers:start
```

<a name="Data_Store"></a>Data store
=======================

-   **Data store platform** MongoDB - tokumx
-   **Data replication strategy** 3 node replica-set cluster accounting-tokumx[2-4].snc1. The cluster has one primary and two secondaries.
-   **Data backup** yes

<a name="Standard_Operating_Procedures"></a>Standard Operating Procedures
=======================

<a name="Deployment"></a>Deployment
=======================

Deployment is completely automated using mergebot and [deploybot](https://github.groupondev.com/release-engineering/deploy-bot/blob/master/README.md). RAPT owns these tools and is in the loop.

All FED services are deployed via Capistrano, using our setup called [Spinderella](https://github.groupondev.com/finance-engineering/spinderella).  It takes care of all standard tasks, including sox-inscope requirements and creating logbook tickets via the messagebus.

We are non-core and generally restrict deploys to Mon-Thu, business hours and Friday mornings.

Deployments are zero downtime and fail safe (to the currently deployed branch).

If you want to revert to a previous release, simply use the "Retry Deploy" inside of JIRA (this is all part of using deploybot)


<a name="Adding_Capacity"></a>Adding Capacity
=======================

#### To add another app box to the backbeat cluster

1. Get a VM (or a real box), edit host file to match accounting-worker2.snc1(hostclass and everything from monitors to end of file)
2. Roll the hosts.
3. Open the console on your machine, open [spinderella](https://github.groupondev.com/finance-engineering/spinderella)
```
    SILENT=true bundle exec cap torquebox:backbeat:production immutant:install HOSTS=%host_name%
    SILENT=true bundle exec cap torquebox:backbeat:production deploy:setup HOSTS=%host_name%
    SILENT=true bundle exec cap torquebox:backbeat:production deploy:install HOSTS=%host_name%
```
4. Open a JIRA ticket to add the host behind this vip: accounting-backbeat-vip.snc1


#### To add another box to the tokumx cluster

1. Get a VM (or a real box), edit host file to match accounting-tokumx2.snc1(hostclass and everything from monitors to end of file)
2. Roll the host.
3. Find out the current primary host for the cluster
```
ssh naren@accounting-tokumx2.snc1
mongo # opens mongo shell
rs.status() # prints the status of replica set including which node is primary
```
4. ssh to the primary node and add the newly created node to the replica set
```
ssh naren@%primary host%
mongo # opens mongo shell
rs.add(%new host%)
rs.status() # this will show the new host is initializing
```

<a name="Troubleshooting"></a>Troubleshooting
=======================


## Runbook (we will keep filling this out as we go)

| Severity | Check Name | Problem/Alert | Immediate action | Directions to fix | Monitoring |
| -------- | ---------- | ------------- | ---------------- | ----------------- | ---------- |
| 3 | | jboss is down | | [Restart JBoss](#restart_jboss) | |

##### Legend
| Severity | Meaning |
| -------- | ------- |
| 1 - high | Bleeding money |
| 2 - med high  | Money is being lost |
| 3 - medium | Could be losing money |
| 4 - med low | Future money being lost |
| 5 - low | Money will be lost if nothing is done |

### Directions to Fix
<a name="restart_jboss">Restart JBoss</a>
```
ssh jboss@accounting-worker{1-3}.snc1
/usr/local/etc/init.d/something_jboss restart
```

Sometimes during restart it doesn't stop hornetq (it hangs), you can kill -9 it 
if look at the server logs the last thing it says is stoping hornetq and never says jboss has stopped - /var/groupon/jboss/accounting/logs/server.log (as jboss - can use cdl command to get to directory)


<a name="restart_jboss_zero_downtime">Restart JBoss with Zero Downtime</a>

Backbeat web endpoints are behind a load balancer - accounting-backbeat-vip.snc1. There are multiple hosts behind this vip with an instace of JBoss running on each host. JBoss on an individual host can be restarted without taking backbeat down. Follow these steps to restart JBoss on all hosts with zero downtime

```        
clone the spindererlla repo https://github.groupondev.com/finance-engineering/spinderella
run 'bundle exec cap torquebox:backbeat:production jboss:restart'
```

### Other Important Links
- [Splunk Dashboard](https://splunk-snc1.groupondev.com/en-US/app/search/FED)
- System graphs:
    - [sidekiq queue latency](https://grapher-snc1.groupondev.com/graph/metric!accounting_sidekiq_latency_sidekiq_latency/accounting-snc1/accounting-utility2.snc1)
	- [accounting-worker1.snc1](https://grapher-snc1.groupondev.com/accounting-snc1/accounting-worker1.snc1)
	- [accounting-worker2.snc1](https://grapher-snc1.groupondev.com/accounting-snc1/accounting-worker2.snc1)
	- [accounting-worker3.snc1](https://grapher-snc1.groupondev.com/accounting-snc1/accounting-worker3.snc1)
	- [accounting-tokumx2.snc1](https://grapher-snc1.groupondev.com/accounting-snc1/accounting-tokumx2.snc1)
	- [accounting-tokumx3.snc1](https://grapher-snc1.groupondev.com/accounting-snc1/accounting-tokumx3.snc1)
	- [accounting-tokumx4.snc1](https://grapher-snc1.groupondev.com/accounting-snc1/accounting-tokumx4.snc1)
    - [general-redis1.snc1](https://grapher-snc1.groupondev.com/redis-snc1/general-redis1.snc1)
    - [general-redis2.snc1](https://grapher-snc1.groupondev.com/redis-snc1/general-redis2.snc1)
- Service Portal: https://service-portal.groupondev.com/services/backbeat
- [PagerDuty] (https://groupon.pagerduty.com/schedules#PB4WS3F)
