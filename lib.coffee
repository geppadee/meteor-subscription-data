checkPath = (path) ->
  if _.isString path
    check path, Match.NonEmptyString

    throw new Match.Error "Cannot modify '#{path}'." if path in ['_id', '_connectionId']

  else
    update = path

    check update, Object

    for field, value of update
      throw new Match.Error "Cannot modify '#{field}'." if field in ['_id', '_connectionId']

      # We do not allow MongoDB operators.
      throw new Match.Error "Invalid field name '#{field}'." if field[0] is '$'

  true

checkSubscriptionDataId = (subscriptionDataId) ->
  check subscriptionDataId, Match.NonEmptyString

  splits = subscriptionDataId.split '_'

  throw new Match.Error "Invalid subscriptionDataId '#{subscriptionDataId}'." if splits.length isnt 2

  check splits[0], Match.DocumentId
  check splits[1], Match.DocumentId

  true

SUBSCRIPTION_ID_REGEX = /_.+?$/

share.handleMethods = (connection, collection, subscriptionDataId) ->
  data: (path, equalsFunc) ->
    getData = (fields) ->
      data = collection.findOne subscriptionDataId,
        fields: fields

      return data unless data

      # We have to query with "_id" included for reactivity
      # to work, but we do not want to expose it.
      # Additionally, we make sure that "_connectionId" is
      # never exposed (it could be if path == "_connectionId").
      _.omit data, '_id', '_connectionId'

    if path?
      # A small optimization for the common case.
      if _.isString path
        fields = {}
        fields[path] = 1
      else
        fields =
          _connectionId: 0

      DataLookup.get ->
        getData fields
      ,
        path, equalsFunc
    else
      getData
        _connectionId: 0

  setData: (path, value) ->
    if value is undefined
      args = [subscriptionDataId, path]
    else
      args = [subscriptionDataId, path, value]

    connection.apply '_subscriptionDataSet', args, (error) =>
      console.error "_subscriptionDataSet error", error if error

share.subscriptionDataMethods = (collection) ->
  _subscriptionDataSet: (subscriptionDataId, path, value) ->
    if Meteor.isClient or @connection?.id
      check subscriptionDataId, Match.DocumentId
    else
      check subscriptionDataId, Match.Where checkSubscriptionDataId
    check path, Match.Where checkPath
    check value, Match.Any

    if Meteor.isClient
      # @connection is available only on the server side, but this is OK,
      # because on the client side "_connectionId" field does not exist
      # anyway (it is not published), so {_connectionId: null} in fact does
      # exactly the right thing: finds documents without "_connectionId".
      connectionId = null
    else if @connection?.id
      # Server-side call from the client. "subscriptionDataId" is only
      # "subscriptionId" so we reconstruct whole "subscriptionDataId".
      connectionId = @connection?.id
      subscriptionDataId = "#{connectionId}_#{subscriptionDataId}"
    else
      # On the server side @connection does not exist when method is called
      # from the server side (for example, from the publish function) but
      # we can get "connectionId" from "subscriptionDataId".
      connectionId = subscriptionDataId.replace SUBSCRIPTION_ID_REGEX, ''

    if _.isString path
      update = {}
      if value is undefined
        update.$unset = {}
        update.$unset[path] = ''
      else
        update.$set = {}
        update.$set[path] = value

    # We checked that the "path" is an object.
    else
      # We are replacing the whole document, so we have to add
      # "_connectionId", otherwise it will be removed.
      update = _.extend path,
        _connectionId: connectionId

    # We make sure (on the server side) that "_connectionId" matches current
    # connection to prevent malicious requests who guess the "subscriptionDataId"
    # to modify the state of other subscriptions. This is not strictly needed
    # though because on the server "subscriptionDataId" contains "connectionId".
    collection.update
      _id: subscriptionDataId
      _connectionId: connectionId
    ,
      update
