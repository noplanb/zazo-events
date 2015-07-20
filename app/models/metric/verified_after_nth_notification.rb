class Metric::VerifiedAfterNthNotification < Metric::Base
  attr_accessor :users_data

  after_initialize :set_attributes
  validates :users_data, presence: true

  def generate
    temp_table_drop
    temp_table_create
    results
  end

  protected

  def run(*params)
    Event.connection.select_all Event.send :sanitize_sql_array, params
  end

  def results
    run <<-SQL
      SELECT
        messages.msg_order,
        COUNT(*)
      FROM events
        INNER JOIN _temp_messages messages ON messages.user_id = events.initiator_id
      WHERE name && ARRAY['verified']::VARCHAR[] AND
        messages.sent_at < events.triggered_at AND
        messages.next_sent_at > events.triggered_at
      GROUP BY messages.msg_order
    SQL
  end

  def temp_table_create
    run <<-SQL
      CREATE TEMP TABLE _temp_messages AS
        SELECT * FROM (
          VALUES #{temp_table_values}
        ) AS t (user_id, msg_order, sent_at, next_sent_at);
    SQL
  end

  def temp_table_drop
    run <<-SQL
      DROP TABLE IF EXISTS _temp_messages;
    SQL
  end

  def temp_table_values
    users_data.inject('') do |memo, row|
      memo += ',' unless memo.empty?
      memo + "('#{row['user_id']}',#{row['msg_order']}::INT,'#{row['sent_at']}'::TIMESTAMP,'#{row['next_sent_at']}'::TIMESTAMP)"
    end
  end

  def set_attributes
    @users_data = attributes['users_data']
  end
end
