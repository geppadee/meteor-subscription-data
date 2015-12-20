SubscriptionData = new Mongo.Collection null

originalPublish = Meteor.publish
Meteor.publish = (name, publishFunction) ->
  originalPublish name, (args...) ->
    publish = @

    # If it is an unnamed publish endpoint, we do not do anything special.
    return publishFunction.apply publish, args unless publish._subscriptionId

    publish.onStop ->
      SubscriptionData.remove publish._subscriptionId

    SubscriptionData.insert
      _id: publish._subscriptionId
      _connectionId: publish.connection.id

    _.extend publish, share.handleMethods SubscriptionData, publish._subscriptionId

    publishFunction.apply publish, args

Meteor.publish null, ->
  handle = SubscriptionData.find(
    _connectionId: @connection.id
  ,
    fields:
      _connectionId: 0
  ).observeChanges
    added: (id, fields) =>
      @added '_subscriptionData', id, fields
    changed: (id, fields) =>
      @changed '_subscriptionData', id, fields
    removed: (id, fields) =>
      @removed '_subscriptionData', id

  @onStop =>
    handle.stop()

  @ready()

Meteor.methods share.subscriptionDataMethods SubscriptionData
