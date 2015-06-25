class Metric::InvitationFunnel < Metric::Base
  def self.type
    :invitation_funnel
  end

  def generate
    {
      verified_sent_invitations: verified_sent_invitations[0],
      average_invitations_count: average_invitations_count,
      invited_to_registered:     invited_to_registered[0],
      registered_to_verified:    registered_to_verified[0]
    }
  end

  protected

  def query(sql)
    Event.connection.select_all sql
  end

  def verified_sent_invitations
    query <<-SQL
      WITH invited AS (
        SELECT
          initiator_id invitee,
          triggered_at
        FROM events
        WHERE name @> ARRAY['user', 'invited']::VARCHAR[]
      ), verified AS (
        SELECT
          DISTINCT events.initiator_id initiator,
          MIN(events.triggered_at) becoming_verified
        FROM events
          INNER JOIN invited ON events.initiator_id = invited.invitee
        WHERE name @> ARRAY['user', 'verified']::VARCHAR[]
        GROUP BY initiator_id
      ), inviters AS (
        SELECT
          DISTINCT events.initiator_id inviter,
          MIN(events.triggered_at) first_invitation
        FROM events
          INNER JOIN invited ON events.target_id = invited.invitee
        WHERE
          name @> ARRAY['user', 'invitation_sent']::VARCHAR[] AND
          EXTRACT(EPOCH FROM events.triggered_at - invited.triggered_at) < 1
        GROUP BY inviter
      ), verified_not_inviters AS (
        SELECT
          verified.initiator,
          verified.becoming_verified
        FROM verified
          LEFT OUTER JOIN inviters ON verified.initiator = inviters.inviter
        WHERE inviters.inviter IS NULL
      ), verified_sent_invitations AS (
          SELECT
            COUNT(*) verified_sent_invitations,
            ROUND(AVG(EXTRACT(EPOCH FROM
              inviters.first_invitation -
              verified.becoming_verified) / 3600)::numeric) avg_delay_in_hours
          FROM verified
            INNER JOIN inviters ON verified.initiator = inviters.inviter
      ) SELECT
          (SELECT COUNT(*) FROM verified) total_verified,
          verified_sent_invitations,
          avg_delay_in_hours,
          (SELECT COUNT(*) FROM verified_not_inviters) verified_not_invite,
          COUNT(*) verified_not_invite_more_6_weeks_old
        FROM verified_not_inviters
          CROSS JOIN verified_sent_invitations
        WHERE becoming_verified < NOW() - INTERVAL '6 weeks'
        GROUP BY verified_sent_invitations, avg_delay_in_hours
    SQL
  end

  def average_invitations_count
    query <<-SQL
      WITH invited AS (
        SELECT
          initiator_id invitee,
          triggered_at
        FROM events
        WHERE name @> ARRAY['user', 'invited']::VARCHAR[]
      ), verified AS (
        SELECT
          DISTINCT events.initiator_id initiator,
                   MIN(events.triggered_at) becoming_verified
        FROM events
          INNER JOIN invited ON events.initiator_id = invited.invitee
        WHERE name @> ARRAY['user', 'verified']::VARCHAR[]
        GROUP BY initiator_id
      ), inviters AS (
        SELECT
          events.initiator_id inviter,
          events.target_id invitee,
          events.triggered_at invite_sent
        FROM events
          INNER JOIN invited ON events.target_id = invited.invitee
        WHERE
          name @> ARRAY['user', 'invitation_sent']::VARCHAR[] AND
          EXTRACT(EPOCH FROM events.triggered_at - invited.triggered_at) < 1
      ), group_by_weeks AS (
        SELECT
          EXTRACT(days FROM (inviters.invite_sent - verified.becoming_verified) / 7) + 1 week,
          verified.initiator
        FROM verified
          INNER JOIN inviters ON verified.initiator = inviters.inviter
      ), count_by_six_weeks AS (
        SELECT
          week::TEXT,
          initiator,
          COUNT(initiator) invitations_count
        FROM group_by_weeks
          INNER JOIN generate_series(1, 6) number ON number = group_by_weeks.week
        GROUP BY week, initiator
      ), count_after_six_weeks AS (
        SELECT
          'after 6 weeks'::TEXT week_after_verified,
          initiator,
          COUNT(*) invitations_count
        FROM group_by_weeks
        WHERE week > 6
        GROUP BY initiator
      ), count_by_weeks AS (
        SELECT *
        FROM count_by_six_weeks
        UNION
          SELECT *
          FROM count_after_six_weeks
      ) SELECT
          week week_after_verified,
          ROUND(SUM(invitations_count) /
                (SELECT COUNT(*) FROM count_by_weeks), 2) avg_invitations_count
        FROM count_by_weeks
        GROUP BY week
        ORDER BY week
    SQL
  end

  def invited_to_registered
    query <<-SQL
      WITH invited AS (
        SELECT
          initiator_id invitee,
          triggered_at
        FROM events
        WHERE name @> ARRAY['user', 'invited']::VARCHAR[]
      ), registered AS (
        SELECT
          DISTINCT events.initiator_id initiator,
          MIN(events.triggered_at) becoming_registered
        FROM events
          INNER JOIN invited ON events.initiator_id = invited.invitee
        WHERE name @> ARRAY['user', 'registered']::VARCHAR[]
        GROUP BY initiator_id
      ) SELECT
          (SELECT COUNT(*) FROM invited) total_invited,
          COUNT(*) invited_that_register,
          ROUND(AVG(EXTRACT(EPOCH FROM
            registered.becoming_registered -
            invited.triggered_at) / 3600)::numeric) avg_delay_in_hours
        FROM registered
          INNER JOIN invited ON registered.initiator = invited.invitee
    SQL
  end

  def registered_to_verified
    query <<-SQL
      WITH invited AS (
        SELECT
          initiator_id invitee,
          triggered_at
        FROM events
        WHERE name @> ARRAY['user', 'invited']::VARCHAR[]
      ), registered AS (
        SELECT
          DISTINCT
          events.initiator_id initiator,
          MIN(events.triggered_at) becoming_registered
        FROM events
          INNER JOIN invited ON events.initiator_id = invited.invitee
        WHERE name @> ARRAY['user', 'registered']::VARCHAR[]
        GROUP BY initiator_id
      ), verified AS (
        SELECT
          initiator_id initiator,
          becoming_registered,
          MIN(events.triggered_at) becoming_verified
        FROM events
          INNER JOIN registered ON events.initiator_id = registered.initiator
        WHERE name @> ARRAY['user', 'verified']::VARCHAR[]
        GROUP BY initiator_id, becoming_registered
      ) SELECT
          (SELECT COUNT(*) FROM registered) total_registered,
          (SELECT COUNT(*) FROM verified) registered_that_verify,
          ROUND(AVG(EXTRACT(EPOCH FROM
            becoming_verified -
            becoming_registered) / 60)::numeric) avg_delay_in_minutes
        FROM verified
    SQL
  end
end