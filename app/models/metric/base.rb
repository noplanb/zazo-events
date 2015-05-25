class Metric::Base
  extend ActiveModel::Callbacks
  include ActiveModel::Validations
  attr_reader :attributes

  define_model_callbacks :initialize

  def initialize(attributes = {})
    run_callbacks :initialize do
      @attributes = attributes.stringify_keys
    end
  end

  def generate
  end
end
