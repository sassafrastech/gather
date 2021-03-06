# frozen_string_literal: true

require "rails_helper"

describe CommunityPolicy do
  describe "permissions" do
    include_context "policy permissions"

    let(:record) { community }

    permissions :index? do
      it "permits super admins only" do
        expect(subject).to permit(super_admin_cmtyX, record)
      end
    end

    permissions :show? do
      it_behaves_like "permits users in cluster"

      it "permits superadmins from outside cluster" do
        expect(subject).to permit(super_admin_cmtyX, record)
      end
    end

    permissions :update? do
      it_behaves_like "permits admins but not regular users"
    end
  end
end
