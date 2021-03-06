# frozen_string_literal: true

module CustomFields
  module Fields
    class TextualField < Field
      def normalize(value)
        value&.strip.presence
      end
    end
  end
end
