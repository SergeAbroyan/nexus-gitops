# 0007. KEDA scales the worker on queue depth

Status: accepted

## Context

The worker spends most of its time waiting on SQS long polls, so CPU stays low
while a backlog grows. A CPU-based HorizontalPodAutoscaler scales too late.

## Decision

KEDA scales the worker with an `aws-sqs-queue` trigger, one replica per five
visible messages, plus CPU and memory triggers as a floor. KEDA reads the queue
with its own Pod Identity, which may only call `GetQueueAttributes` on the job
queue. The base chart skips its HorizontalPodAutoscaler when
`autoscaling.provider` is `keda`.

## Consequences

The worker follows the backlog within seconds and returns to its minimum when
the queue drains. KEDA is one more controller that must be healthy for scaling
to work; the existing minimum replicas keep processing if it is not.
