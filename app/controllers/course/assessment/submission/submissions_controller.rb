# frozen_string_literal: true
class Course::Assessment::Submission::SubmissionsController < \
  Course::Assessment::Submission::Controller
  include Course::Assessment::Submission::SubmissionsControllerServiceConcern

  before_action :authorize_assessment!, only: :create
  skip_authorize_resource :submission, only: [:edit, :update, :auto_grade]
  before_action :authorize_submission!, only: [:edit, :update]
  before_action :load_or_create_answers, only: [:edit, :update]

  delegate_to_service(:update)
  delegate_to_service(:load_or_create_answers)

  def index
    authorize!(:manage, @assessment)
    @submissions = @submissions.includes(:answers, experience_points_record: :course_user)
    @course_students = current_course.course_users.students.with_approved_state.order_alphabetically
  end

  def create
    raise IllegalStateError if @assessment.questions.empty?
    if @submission.save
      redirect_to edit_course_assessment_submission_path(current_course, @assessment, @submission)
    else
      redirect_to course_assessments_path(current_course),
                  danger: t('.failure', error: @submission.errors.full_messages.to_sentence)
    end
  end

  def edit
    return if @submission.attempting?

    calculated_fields = [:submitted_at, :graded_at]
    @submission = @submission.calculated(*calculated_fields)
  end

  def auto_grade
    authorize!(:grade, @submission)
    job = @submission.auto_grade!
    redirect_to(job_path(job.job))
  end

  # Reload current answer to its latest status.
  def reload_answer
    @answer = @submission.answers.find_by(id: answer_id_param)

    if @answer
      @current_question = @answer.question
      @new_answer = @submission.answers.from_question(@current_question.id).last
    else
      render status: :bad_request
    end
  end

  private

  def create_params
    { course_user: current_course_user }
  end

  def authorize_assessment!
    authorize!(:attempt, @assessment)
  end

  def authorize_submission!
    if @submission.attempting?
      authorize!(:update, @submission)
    else
      authorize!(:read, @submission)
    end
  end

  def answer_id_param
    params.permit(:answer_id)[:answer_id]
  end
end
