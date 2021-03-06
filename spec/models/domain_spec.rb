# frozen_string_literal: true

require "rails_helper"

describe Domain do
  describe "factory" do
    it "is valid" do
      expect(create(:domain).communities.size).to eq(1)
    end
  end

  describe "destruction" do
    context "with ownership and mailman list" do
      let!(:domain) { create(:domain) }
      let!(:ownership) { domain.ownerships[0] }
      let!(:list) { create(:group_mailman_list, domain: domain) }

      it "cascades" do
        domain.destroy
        expect { list.reload }.to raise_error(ActiveRecord::RecordNotFound)
        expect { ownership.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
