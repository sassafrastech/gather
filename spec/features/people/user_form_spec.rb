# frozen_string_literal: true

require "rails_helper"

feature "user form", js: true do
  include_context "photo uploads"

  let(:admin) { create(:admin) }
  let(:photographer) { create(:photographer) }
  let(:user) { create(:user, :with_photo) }
  let!(:household) { create(:household, name: "Gingerbread") }
  let!(:household2) { create(:household, name: "Potatoheads") }
  let(:edit_path) { edit_user_path(user) }

  around { |ex| with_user_home_subdomain(actor) { ex.run } }

  before do
    login_as(actor, scope: :user)
  end

  shared_examples_for "editing user" do
    scenario "edit user" do
      visit(edit_path)
      expect_image_upload(mode: :existing, path: /cooper/)
      drop_in_dropzone(fixture_file_path("chomsky.jpg"))
      expect_image_upload(mode: :dz_preview)
      fill_in("First Name", with: "Zoor")
      click_button("Save")

      expect_success
      expect(page).to have_title(/Zoor/)
      expect_photo(/chomsky/)
    end
  end

  context "as admin" do
    let(:actor) { admin }

    it_behaves_like "editing user"
    it_behaves_like "photo upload widget"

    scenario "new user" do
      visit(new_user_path)
      expect_no_image_and_drop_file("cooper.jpg")
      click_button("Save")

      expect_validation_error
      expect_image_upload(mode: :existing, path: /cooper/)
      fill_in("First Name", with: "Foo")
      fill_in("Last Name", with: "Barre")
      fill_in("Email", with: "foo@example.com")
      select2("Ginger", from: "#user_household_id")
      fill_in("Mobile", with: "5556667777")
      click_button("Save")

      expect(page).to have_alert("User created successfully.")
      expect(page).to have_title(/Foo Barre/)
      expect_photo(/cooper/)

      emails = email_sent_by { process_queued_job }
      expect(emails).to be_empty
      expect(User.find_by(email: "foo@example.com")).not_to be_confirmed
    end

    scenario "new user with invite" do
      visit(new_user_path)
      fill_in("First Name", with: "Foo")
      fill_in("Last Name", with: "Barre")
      fill_in("Email", with: "foo@example.com")
      select2("Ginger", from: "#user_household_id")
      fill_in("Mobile", with: "5556667777")
      click_on("Save & Invite")

      expect(page).to have_alert("User created and invited successfully.")

      emails = email_sent_by { process_queued_job }
      expect(emails.map(&:subject)).to eq(["Instructions for Signing in to Gather"])
      expect(User.find_by(email: "foo@example.com")).not_to be_confirmed
    end

    scenario "editing household" do
      visit(edit_path)
      click_on("move them to another household")
      select2("Potatoheads", from: "#user_household_id")
      click_button("Save")

      expect_success
      expect(page).to have_css(%(a.household[href$="/households/#{household2.id}"]))
    end

    scenario "deactivate/activate/delete" do
      visit(edit_path)
      accept_confirm { click_on("Deactivate") }
      expect_success

      visit(edit_path)
      click_link("reactivate")
      expect_success

      visit(edit_path)
      expect(page).not_to have_content("reactivate")
      accept_confirm { click_on("Delete") }
      expect_success

      expect { user.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  context "as photographer" do
    let(:actor) { photographer }

    scenario "update photo" do
      visit(user_path(user))
      click_on("Edit Photo")
      expect_image_upload(mode: :upload_message)
      drop_in_dropzone(fixture_file_path("chomsky.jpg"))
      expect_image_upload(mode: :dz_preview)
      click_button("Save")
      expect_success
      expect_photo(/chomsky/)
    end
  end

  context "as regular user" do
    let(:actor) { user }

    it_behaves_like "editing user"
  end
end
