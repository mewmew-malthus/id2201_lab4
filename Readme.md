# Lab 4

### Notes and Miscellaneous
First, I notice that in section 3 the document says we do not need to report when a slave crashes. This is obviously false, or intentionally misleading.

Ok, so it was intentionally misleading. Multicast recovery is not supposed to work. Why?
The election requires that all workers have the same view, and that the view is accurate. The most likely way this fails is a worker crashes, then when the election happens, the crashed leader is elected. Of course, that case is not exposed in our lab. Really, the color is dependent on all of the previous messages, and some panels do not receive messages during a crash.


Things to handle:
1. Lost Messages
2. Failure Detector does not work
3. Incorrect Messages

## Lost Messages:
BEAM guarantees the messages are delivered if FIFO order. Because each message already has an order number, it is trivial to detect a message has been missed - the N value attached to the message will increment by more than 1. In that case, the process requests state from the Leader, and updates its state to match.