# frozen_string_literal: true

require "rails_helper"

describe Reservations::Rules::RuleSet do
  let(:resource1) { create(:resource) }
  let(:user) { create(:user) }
  let(:rule_set) { described_class.build_for(resource: resource1, kind: nil, reserver: user) }

  describe "#errors" do
    let(:rule1) { double(check: [:starts_at, "foo"]) }
    let(:rule2) { double(check: [:starts_at, "bar"]) }
    let(:rule3) { double(check: true) }
    let(:rule4) { double(check: [:base, "baz"]) }
    subject(:errors) { rule_set.errors(nil) }

    before { allow(rule_set).to receive(:rules).and_return([rule1, rule2, rule3, rule4]) }

    it { is_expected.to contain_exactly([:starts_at, "foo"], [:starts_at, "bar"], [:base, "baz"]) }
  end

  describe "#access_level" do
    subject(:access_level) { rule_set.access_level }

    context "with reserver in same community" do
      context "with other communities forbidden" do
        let!(:p1) { create(:reservation_protocol, resources: [resource1], other_communities: "forbidden") }
        it { is_expected.to eq("ok") }
      end

      context "with no protocols" do
        let!(:p1) { create(:reservation_protocol, resources: [resource1]) }
        it { is_expected.to eq("ok") }
      end
    end

    context "with reserver in different community" do
      let(:user) { create(:user, community: create(:community)) }

      context "with multiple protocols" do
        let!(:p1) { create(:reservation_protocol, resources: [resource1], other_communities: "read_only") }
        let!(:p2) { create(:reservation_protocol, resources: [resource1], other_communities: "forbidden") }
        let!(:p3) { create(:reservation_protocol, resources: [resource1], max_lead_days: 60) }
        it { is_expected.to eq("forbidden") }
      end

      context "with no protocols" do
        let!(:p1) { create(:reservation_protocol, resources: [resource1]) }
        it { is_expected.to eq("ok") }
      end
    end
  end

  shared_examples_for "fixed time rule" do
    subject(:value) { rule_set.send(rule_name)&.strftime("%T") }

    context "with multiple rules" do
      let!(:p1) do
        create(:reservation_protocol, resources: [resource1], rule_name => "11:00am",
                                      created_at: Time.current - 10)
      end
      let!(:p2) do
        create(:reservation_protocol, resources: [resource1], rule_name => "10:00am")
      end
      it { is_expected.to eq("11:00:00") }
    end

    context "with no rules" do
      it { is_expected.to be_nil }
    end
  end

  describe "#fixed_start_time" do
    let(:rule_name) { :fixed_start_time }
    it_behaves_like "fixed time rule"
  end

  describe "#fixed_end_time" do
    let(:rule_name) { :fixed_end_time }
    it_behaves_like "fixed time rule"
  end

  describe "#rules_with_name" do
    subject(:value) { rule_set.rules_with_name(:pre_notice).map(&:value) }

    context "with multiple rules" do
      let!(:p1) do
        create(:reservation_protocol, resources: [resource1], pre_notice: "Foo",
                                      created_at: Time.current - 10)
      end
      let!(:p2) do
        create(:reservation_protocol, resources: [resource1], pre_notice: "Bar")
      end
      it { is_expected.to eq(%w[Foo Bar]) }
    end

    context "with no rules" do
      it { is_expected.to be_empty }
    end
  end

  describe "#requires_kind?" do
    subject(:value) { rule_set.requires_kind? }

    context "with multiple rules" do
      let!(:p1) do
        create(:reservation_protocol, resources: [resource1], requires_kind: nil,
                                      created_at: Time.current - 10)
      end
      let!(:p2) do
        create(:reservation_protocol, resources: [resource1], requires_kind: true)
      end
      it { is_expected.to be true }
    end

    context "with one nil rule" do
      let!(:p1) do
        create(:reservation_protocol, resources: [resource1], requires_kind: nil)
      end
      it { is_expected.to be false }
    end

    context "with no rules" do
      it { is_expected.to be false }
    end
  end
end
