# Own a library view's work

Use one stable window Id per application. Recreating that Id destroys the old
window and releases its owned work. Hide and Minimize keep application state and
subscriptions; closing the window destroys them.

| Work | Ownership |
| --- | --- |
| Service or model subscription | `window:Give(connectionOrUnsubscribe)` |
| One delayed update | `cancel = window:Delay(seconds, callback)` |
| Latest update after activity pauses | `schedule, cancel = window:Debounce(seconds, callback)` |
| Domain cleanup with dependent steps | One `window:OnDestroy(function() ... end)` |

Delay and Debounce clean up completed tasks automatically. Their cancellation
functions are idempotent. Debounce retains the latest arguments, including nil
positions; cancellation clears those arguments. A callback can schedule another
update without losing it. Calls to a retained schedule function return false
after window destruction.

Use Debounce for activity that pauses, such as typing or model notifications. A
continuous heartbeat can keep postponing a trailing debounce forever. Instead,
use a `queued` flag plus `Delay` to update at a bounded cadence, as shown in the
[activity example](../ui-lib/examples/activity.lua). The [player finder](../ui-lib/examples/debounce.lua)
demonstrates event subscriptions and a typing debounce.

Keep scheduled callbacks short. Native operations need their own cancellation
contract and stale-result check: retain a request generation and check it plus
`window.Alive` after the operation returns. Closing a view does not roll back
domain side effects or destroy a shared client. Give those actions explicit
application controls.

The [canonical lifecycle reference](UI_LIBRARY.md#lifecycle) explains early
release and the distinction between view ownership and UAI tool execution limits.
