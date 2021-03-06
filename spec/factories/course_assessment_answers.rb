# frozen_string_literal: true
FactoryGirl.define do
  factory :course_assessment_answer, class: Course::Assessment::Answer,
                                     parent: :course_discussion_topic do
    transient do
      assessment { build(:assessment, course: course) }
      # The creator in userstamps must be persisted.
      creator { create(:user) }
      submission_traits []
    end

    submission do
      traits = *submission_traits
      options = traits.extract_options!
      options[:assessment] = question.assessment
      options[:creator] = creator
      build(:course_assessment_submission, *traits, options)
    end
    question { build(:course_assessment_question, assessment: assessment) }

    after(:build) do |answer, evaluator|
      answer.course = evaluator.course
    end

    trait :submitted do
      submission_traits :submitted
      after(:build) do |answer| # rubocop:disable Style/SymbolProc
        answer.finalise!
      end
    end

    trait :graded do
      submitted
      submission_traits :graded
      after(:build) do |answer| # rubocop:disable Style/SymbolProc
        answer.publish!
      end
    end
  end
end
