# frozen_string_literal: true

require "rails_helper"

describe "household form" do
  before do
    use_user_subdomain(actor)
    login_as(actor, scope: :user)
  end

  describe "create" do
    shared_examples_for "creates household" do |community_name|
      scenario "new household", js: true do
        visit(new_household_path)
        fill_in("Household Name", with: "Pump")
        select(community_name, from: "Community") if community_name
        fill_in("Unit Number", with: "33")
        fill_in("Garage Number(s)", with: "7")
        click_button("Save")
        expect_success
        select_lens(:community, community_name) if community_name
        click_on("Pump")
        expect(page).to have_css("table.key-value", text: community_name) if community_name
      end
    end

    context "as admin with single community" do
      let(:actor) { create(:admin) }
      it_behaves_like "creates household"
    end

    context "as cluster admin with multiple communities" do
      let!(:actor) { create(:cluster_admin) }
      let!(:other_community) { create(:community, name: "Foo") }
      it_behaves_like "creates household", "Foo"
    end
  end

  describe "update" do
    let(:user) { create(:user) }
    let(:admin) { create(:admin) }

    shared_examples_for "updates household" do
      scenario js: true do
        visit(edit_household_path(user.household))
        within(".household_emergency_contacts") do
          fill_in("Name *", with: "Lori", exact: true)
          fill_in("Relationship to Household", with: "Mom")
          fill_in("Main Phone", with: "7776665555")
          fill_in("Location", with: "Placey Place")
        end
        click_button("Save")
        expect(page).to have_content("updated successfully")
      end
    end

    context "with single community" do
      context "as basic user" do
        let!(:actor) { user }
        it_behaves_like "updates household"
      end

      context "as admin" do
        let!(:actor) { admin }
        it_behaves_like "updates household"
      end
    end

    context "with multiple communities" do
      let!(:other_community) { create(:community, name: "Foo") }

      context "as basic user" do
        let!(:actor) { user }
        it_behaves_like "updates household"
      end

      context "as admin" do
        let!(:actor) { admin }
        it_behaves_like "updates household"
      end
    end
  end

  context "emergency contact phone number handling" do
    let!(:actor) { create(:admin) }

    before do
      Defaults.community.update!(country_code: "NZ")
    end

    scenario "it defaults to that country in country dropdown", js: true do
      visit(new_household_path)
      fill_in("Household Name", with: "Pump")
      fill_in("Unit Number", with: "33")
      within(all(".household_emergency_contacts .nested-fields")[0]) do
        expect(page).to have_select("Country", selected: "New Zealand")
        fill_in("Name *", with: "Lori", exact: true)
        fill_in("Relationship to Household", with: "Mom")
        fill_in("Location", with: "Placey Place")
        fill_in("Main Phone", with: "21345678")
      end
      click_link("Add Emergency Contact")
      within(all(".household_emergency_contacts .nested-fields")[1]) do
        expect(page).to have_select("Country", selected: "New Zealand")
        fill_in("Name *", with: "Lunz", exact: true)
        fill_in("Relationship to Household", with: "Friar")
        fill_in("Location", with: "Overdere")
        select("Canada", from: "Country")
        fill_in("Main Phone", with: "7091234444")
      end
      click_button("Save")
      click_on("Pump")
      expect(page).to have_content("021 345 678") # Formatted for NZ
      expect(page).to have_content("+1 (709) 123-4444 (Canada)") # Formatted for Canada
    end
  end
end
