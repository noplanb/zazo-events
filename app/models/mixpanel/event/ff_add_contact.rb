class Mixpanel::Event::FfAddContact < Mixpanel::Event
  def user
    e.initiator_id
  end

  def data
    { 'triggered_by' => 'api' }
  end
end