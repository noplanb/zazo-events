class Metric::UsageByActiveUsers < Metric::Base
  def generate
    total_messages.reduce({}) do |memo, (time_frame, messages_count)|
      users_count = users_sent_message[time_frame]
      memo[time_frame] = messages_count.to_f / users_count.to_f
      memo
    end
  end

  private

  def total_messages
    @total_messages ||= messages_sent_scope.count
  end

  def users_sent_message
    @users_sent_message ||= messages_sent_scope.count("data->>'sender_id'")
  end

  def messages_sent_scope
    Event.by_name(%w(video s3 uploaded)).send(:"group_by_#{group_by}", :triggered_at)
  end
end