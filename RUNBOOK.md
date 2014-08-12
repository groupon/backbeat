# Backbeat Runbook

## Overview

### Backbeat

Backbeat is a workflow service (a la Amazon Simple Workflow).  It's used by the accounting service and VAT Invoicing service (And maybe other things).

Written in Ruby, uses Mongo (tokumx) for its db, Sidekiq for async workers and Delayed Job for scheduled tasks (DJ runs on accounting-worker1.snc1).

### Architecture
	Hosts:	accounting-worker{1-3}.snc1 (jruby with grape inside of JBoss)
	Database: accounting-tokumx{1-3}.snc1 (tokumx, a mongo replacement)
    Async Jobs: general-redis-vip.snc1
	VIP: accounting-backbeat-vip.snc1

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

	ssh jboss@accounting-worker{1-3}.snc1
	/usr/local/etc/init.d/something_jboss restart
	
sometimes during restart it doesn't stop hornetq (it hangs), you can kill -9 it 
if look at the server logs the last thing it says is stoping hornetq and never says jboss has stopped - /var/groupon/jboss/accounting/logs/server.log (as jboss - can use cdl command to get to directory)

### Other Important Links
- [Splunk Dashboard](https://splunk-snc1.groupondev.com/en-US/app/search/FED)
- System graphs:
    - [sidekiq queue latency](https://grapher-snc1.groupondev.com/graph/metric!accounting_sidekiq_latency_sidekiq_latency/accounting-snc1/accounting-utility2.snc1)
	- [accounting-worker1.snc1](https://grapher-snc1.groupondev.com/accounting-snc1/accounting-worker1.snc1)
	- [accounting-worker2.snc1](https://grapher-snc1.groupondev.com/accounting-snc1/accounting-worker2.snc1)
	- [accounting-worker3.snc1](https://grapher-snc1.groupondev.com/accounting-snc1/accounting-worker3.snc1)
	- [accounting-tokumx1.snc1](https://grapher-snc1.groupondev.com/accounting-snc1/accounting-tokumx1.snc1)
	- [accounting-tokumx2.snc1](https://grapher-snc1.groupondev.com/accounting-snc1/accounting-tokumx2.snc1)
	- [accounting-tokumx3.snc1](https://grapher-snc1.groupondev.com/accounting-snc1/accounting-tokumx3.snc1)
    - [general-redis1.snc1](https://grapher-snc1.groupondev.com/redis-snc1/general-redis1.snc1)
    - [general-redis2.snc1](https://grapher-snc1.groupondev.com/redis-snc1/general-redis2.snc1)
- Service Portal: https://service-portal.groupondev.com/services/backbeat
- [PagerDuty] (https://groupon.pagerduty.com/schedules#PB4WS3F)
