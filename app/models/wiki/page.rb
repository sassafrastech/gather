module Wiki
  class Page < ActiveRecord::Base
    acts_as_tenant :cluster
    acts_as_wiki_page

    belongs_to :community
  end
end
