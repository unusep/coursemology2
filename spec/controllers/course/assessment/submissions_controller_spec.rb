# frozen_string_literal: true
require 'rails_helper'

RSpec.describe Course::Assessment::SubmissionsController do
  let!(:instance) { create(:instance) }

  with_tenant(:instance) do
    let(:user) { create(:user) }
    let!(:course) { create(:course, creator: user) }
    let(:categories) { create_list(:course_assessment_category, 2, course: course) }

    before { sign_in(user) }

    describe '#index' do
      context 'when no category is specified' do
        before { get :index, course_id: course }

        it 'sets the category to the first category' do
          first_category = course.assessment_categories.first
          expect(controller.instance_variable_get(:@category)).to eq(first_category)
        end
      end

      context 'when a category is specified' do
        let(:category) { categories.first }
        let(:tab) { create(:course_assessment_tab, course: course, category: category) }
        let(:assessment) { create(:assessment, :with_all_question_types, course: course, tab: tab) }
        let!(:submission) { create(:course_assessment_submission, :graded, assessment: assessment) }
        before { get :index, course_id: course, category: category }

        it 'sets the category to be the specified category' do
          expect(controller.instance_variable_get(:@category)).to eq(category)
        end

        it 'loads the submissions from assessments in the specified category' do
          submissions = controller.instance_variable_get(:@submissions)
          expect(submissions).to contain_exactly(submission)
        end
      end
    end
  end
end
