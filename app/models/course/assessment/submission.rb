# frozen_string_literal: true
class Course::Assessment::Submission < ActiveRecord::Base
  include Workflow

  acts_as_experience_points_record
  include Course::Assessment::Submission::ExperiencePointsDisplayConcern

  after_save :auto_grade_submission, if: :submitted?
  after_create :send_notification

  workflow do
    state :attempting do
      event :finalise, transitions_to: :submitted
    end
    state :submitted do
      event :unsubmit, transitions_to: :attempting
      event :publish, transitions_to: :graded
    end
    state :graded do
      event :unsubmit, transitions_to: :attempting
    end
  end

  schema_validations except: [:creator_id, :assessment_id]
  validate :validate_consistent_user, :validate_unique_submission, on: :create

  belongs_to :assessment, inverse_of: :submissions

  # @!attribute [r] answers
  #   The answers associated with this submission. There can be more than one answer per submission,
  #   this is because every answer is saved over time. Use the {.latest} scope of the answers if
  #   only the latest answer for each question is desired.
  has_many :answers, class_name: Course::Assessment::Answer.name, dependent: :destroy,
                     inverse_of: :submission do
    include Course::Assessment::Submission::AnswersConcern
  end
  has_many :multiple_response_answers,
           through: :answers, inverse_through: :answer, source: :actable,
           source_type: Course::Assessment::Answer::MultipleResponse.name
  has_many :text_response_answers,
           through: :answers, inverse_through: :answer, source: :actable,
           source_type: Course::Assessment::Answer::TextResponse.name
  has_many :programming_answers,
           through: :answers, inverse_through: :answer, source: :actable,
           source_type: Course::Assessment::Answer::Programming.name

  # @!attribute [r] graders
  #   The graders associated with this submission.
  has_many :graders, through: :answers, class_name: User.name

  accepts_nested_attributes_for :answers

  # @!attribute [r] submitted_at
  #   Gets the time the submission was submitted.
  #   @return [Time]
  calculated :submitted_at, (lambda do
    Course::Assessment::Answer.unscope(:order).where do
      course_assessment_answers.submission_id == course_assessment_submissions.id
    end.select { max(course_assessment_answers.submitted_at) }
  end)

  # @!attribute [r] graded_at
  #   Gets the time the submission was graded.
  #   @return [Time]
  calculated :graded_at, (lambda do
    Course::Assessment::Answer.unscope(:order).where do
      course_assessment_answers.submission_id == course_assessment_submissions.id
    end.select { max(course_assessment_answers.graded_at) }
  end)

  # @!method self.by_user(user)
  #   Finds all the submissions by the given user.
  #   @param [User] user The user to filter submissions by
  scope :by_user, (lambda do |user|
    joins { experience_points_record.course_user }.
      where { experience_points_record.course_user.user == user }
  end)

  # @!method self.by_users(user)
  #   @param [Fixnum|Array<Fixnum>] user_ids The user ids to filter submissions by
  scope :by_users, ->(user_ids) { where { creator_id >> user_ids } }

  # @!method self.from_category(category)
  #   Finds all the submissions in the given category.
  #   @param [Course::Assessment::Category] category The category to filter submissions by
  scope :from_category, (lambda do |category|
    where { assessment_id >> category.assessments.select(:id) }
  end)

  scope :from_course, (lambda do |course|
    joins { assessment.tab.category }.where { assessment.tab.category.course == course }
  end)

  # @!method self.ordered_by_date
  #   Orders the submissions by date of creation. This defaults to reverse chronological order
  #   (newest submission first).
  scope :ordered_by_date, ->(direction = :desc) { order(created_at: direction) }

  # @!method self.ordered_by_submitted date
  #   Orders the submissions by date of submission (newest submission first).
  scope :ordered_by_submitted_date, (lambda do
    all.calculated(:submitted_at).order('submitted_at DESC')
  end)

  # @!method self.confirmed
  #   Returns submissions which have been submitted (which may or may not be graded).
  scope :confirmed, -> { where(workflow_state: [:submitted, :graded]) }

  alias_method :finalise=, :finalise!
  alias_method :publish=, :publish!
  alias_method :unsubmit=, :unsubmit!

  # Creates an Auto Grading job for this submission. This saves the submission if there are pending
  # changes.
  #
  # @return [Course::Assessment::Submission::AutoGradingJob] The job instance.
  def auto_grade!
    AutoGradingJob.perform_later(self)
  end

  def unsubmitting?
    !!@unsubmitting
  end

  # The total grade of the submission
  def grade
    latest_answers.map { |a| a.grade || 0 }.sum
  end

  # The latest answer is last answer of the question, ordered by created_at.
  def latest_answers
    answers.group_by(&:question_id).map { |pair| pair[1].last }
  end

  protected

  # Handles the finalisation of a submission.
  #
  # This finalises all the answers as well.
  def finalise(_ = nil)
    answers.select(&:attempting?).each(&:finalise!)
  end

  # Handles the grading of a submission.
  #
  # This grades all the answers as well.
  def publish(_ = nil)
    answers.each do |answer|
      answer.publish! if answer.submitted?
    end
  end

  # Handles the unsubmission of a submitted submission.
  def unsubmit(_ = nil)
    # Skip the state validation in answers.
    @unsubmitting = true

    unsubmit_latest_answers
    self.points_awarded = nil
  end

  private

  # Queues the submission for auto grading, after the submission has changed to the submitted state.
  def auto_grade_submission
    return unless workflow_state_changed?

    execute_after_commit do
      auto_grade!
    end
  end

  # Validate that the submission creator is the same user as the course_user in the associated
  # experience_points_record.
  def validate_consistent_user
    unless course_user && course_user.user == creator
      errors.add(:experience_points_record, :inconsistent_user)
    end
  end

  # Validate that the submission creator does not have an existing submission for this assessment.
  def validate_unique_submission
    existing = Course::Assessment::Submission.find_by(assessment_id: assessment.id,
                                                      creator_id: creator.id)
    if existing
      errors.clear
      errors[:base] << I18n.t('activerecord.errors.models.course/assessment/'\
                              'submission.submission_already_exists')
    end
  end

  def send_notification
    return unless course_user.real_student?

    Course::AssessmentNotifier.assessment_attempted(creator, assessment)
  end

  def unsubmit_latest_answers
    latest_answers.each do |answer|
      answer.unsubmit! if answer.submitted? || answer.graded?
    end
  end
end
