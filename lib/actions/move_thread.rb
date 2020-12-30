require 'pp'

TODO_CHANNEL = 'todo'
DONE_CHANNEL = 'done'
USER_TOKEN = 'xoxb-864327233330-1585744031319-nVOJp2ugmZYVUdtByFHDInwg'

def post_message_for_user(client, user_cache, channel, text, blocks, user_id, reply_to_ts = nil)
  # old block ids won't work
  # actually, blocks are not accepted at all...!?
  # blocks.map! {|block| block.delete(:block_id); block }

  # fetch user's display name

  unless user_cache[user_id]
    result = client.users_info(user: user_id)
    # p('---user---')
    # pp(result)
    unless result[:ok]
      action.logger.error('could not get user info')
      return nil, nil
    end
    user_cache[user_id] = result[:user][:profile][:display_name]
  end

  # post

  result = client.chat_postMessage(
    channel: channel,
    text: text,
    # blocks: blocks,
    username: user_cache[user_id] + ' (via FreiBot)',
    thread_ts: reply_to_ts
  )
  # p('---post---')
  # pp(result)
  unless result[:ok]
    action.logger.error('could not post message')
    return nil, nil
  end

  return user_cache, result[:message][:ts]
end

def move_thread_to_channel(action, channel)
  shortcut_payload = action[:payload]
  shortcut_response_url = shortcut_payload[:response_url]
  shortcut_message = shortcut_payload[:message]
  shortcut_message_ts = shortcut_message[:thread_ts] || shortcut_message[:ts]

  # pp(action)

  client = Slack::Web::Client.new(token: USER_TOKEN)

  # retrieve complete thread

  result = client.conversations_replies(
    channel: shortcut_payload[:channel][:id],
    ts: shortcut_message_ts
  )
  # p('---replies---')
  # pp(result)
  unless result[:ok]
    action.logger.error('could not retrieve thread')
    return { ok: false }
  end
  parent_message, *replies = *result[:messages]

  # repost each single message

  user_cache, new_post_ts = post_message_for_user(
    client,
    {},
    TODO_CHANNEL,
    parent_message[:text],
    parent_message[:blocks],
    parent_message[:user]
  )
  if new_post_ts
    # TODO: check each result
    replies.each do |message|
      user_cache, _ = post_message_for_user(
        client,
        user_cache,
        TODO_CHANNEL,
        message[:text],
        message[:blocks],
        message[:user],
        new_post_ts
      )
    end
  else
    return { ok: false }
  end

  # delete original
  # does not seem to work, either...

  Faraday.post(shortcut_response_url, {
    delete_original: true,
  }.to_json, 'Content-Type' => 'application/json')

  # result = client.chat_delete(channel: shortcut_payload[:channel][:id], ts: shortcut_message_ts, as_user: true)
  # unless result[:ok]
  #   action.logger.error('could not delete thread')
  #   return { ok: false }
  # end

  action.logger.info "moved #{replies.length + 1} messages"

  { ok: true }
end

SlackRubyBotServer::Events.configure do |config|
  config.on :action, 'message_action', 'move-thread-todo' do |action|
    action.logger.info "move-thread-todo shortcut triggered"
    move_thread_to_channel(action, TODO_CHANNEL)
  end

  config.on :action, 'message_action', 'move-thread-done' do |action|
    action.logger.info "move-thread-done shortcut triggered"
    move_thread_to_channel(action, DONE_CHANNEL)
  end
end
