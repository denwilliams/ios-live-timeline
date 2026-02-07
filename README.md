Allows AI agents and other automations to push events to be displayed in a timeline to the user in an iPad.

The purpose is to have background AI agents working on things but keep the user in the loop, also the user can scroll back and check history or search/filter.

Obviously the agents could use regular push notifications but the timeline view isn't helpful in iOS.

If an agent is working on a task it should be able to update the status of that task (removing the past event for that task and moving the new status to the top of the timeline).

The timeline should be newest event at the top, so you scroll down to see old events.

Could possibly use APN to publish events but dont plan to publish this to the app store. Not sure if can use this on dev version.

Future enhancement - allow callback interactions (user presses a button on the screen which calls a webhook to notify the agent of a user decision eg "i found 10 emails from X that seem uninmportant, should I archive them for you [Yes] [No] [Need More details]".

Future enhancement - have a listing of agents you can interact with by sending chat messages (possible voice given that iOS has great voice keyboard support)
