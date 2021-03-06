class ProposalsController < ApplicationController
  include CommentableActions
  include FlagActions

  before_action :parse_tag_filter, only: :index
  before_action :load_categories, only: [:index, :new, :edit, :map, :summary]
  before_action :load_geozones, only: [:edit, :map, :summary]
  before_action :authenticate_user!, except: [:index, :show, :map, :summary]

  invisible_captcha only: [:create, :update], honeypot: :subtitle

  has_orders %w{date_challenges hot_score confidence_score created_at relevance archival_date}, only: :index
  # has_orders %w{confidence_score created_at relevance archival_date}, only: :index
  has_orders %w{most_voted newest oldest}, only: :show

  load_and_authorize_resource
  helper_method :resource_model, :resource_name
  respond_to :html, :js


  def show
    super
    @notifications = @proposal.notifications
  end

  def new
    if params[:problem].present?
      @problem = Problem.find(params[:problem].to_i)
    end
    @proposal.build_problem
  end

  def index_customization
    unless params[:challenge].nil?
      @problem = Problem.find(params[:challenge])
      @proposals_challenge = @problem.proposals.order(cached_votes_up: :desc).page params[:page]
    end
    discard_archived
    load_retired
    load_successful_proposals
    load_featured unless @proposal_successful_exists
  end

  def vote
    @proposal.register_vote(current_user, 'yes')
    set_proposal_votes(@proposal)
  end

  def vote_admin
    pwd = Devise.friendly_token.first(8)
    doc_num = params[:document_number].gsub(".","").gsub("-","").upcase
    email = "#{doc_num}@abre.cl"
    u = User.find_by(document_number: doc_num)
    if u.present?
      @proposal.admin_register_vote(u, 'yes')
    else
      u = User.new(username: params[:username].titleize, email: email, password: pwd, password_confirmation: pwd, confirmed_at: Time.current, terms_of_service: "1", document_number: params[:document_number], phone_number: params[:phone_number])
      if u.save
        @proposal.admin_register_vote(u, 'yes')
      else
        puts ap u.errors.messages
        redirect_to proposals_url(challenge: @proposal.problem.id), alert: t('proposals.alert.user_create_error')
      end
    end
    redirect_to proposals_url(challenge: @proposal.problem.id)
    set_proposal_votes(@proposal)
  end

  def retire
    if valid_retired_params? && @proposal.update(retired_params.merge(retired_at: Time.current))
      redirect_to proposal_path(@proposal), notice: t('proposals.notice.retired')
    else
      render action: :retire_form
    end
  end

  def retire_form
  end

  def vote_featured
    @proposal.register_vote(current_user, 'yes')
    set_featured_proposal_votes(@proposal)
  end

  def summary
    @proposals = Proposal.for_summary
    @tag_cloud = tag_cloud
  end

  private

    def proposal_params
      params.require(:proposal).permit(:title, :responsible_name, :responsible_id, :responsible_phone, :author_id, :question, :summary, :description, :external_url, :video_url, :for_challenge, :responsible_name, :tag_list, :prioritize, :what, :why, :terms_of_service,  :problem_id, geozone_ids: [],  problem_attributes: [:id, :title, :summary, :description, :cause, :consequence, :user_id])
    end

    def retired_params
      params.require(:proposal).permit(:retired_reason, :retired_explanation)
    end

    def valid_retired_params?
      @proposal.errors.add(:retired_reason, I18n.t('errors.messages.blank')) if params[:proposal][:retired_reason].blank?
      @proposal.errors.add(:retired_explanation, I18n.t('errors.messages.blank')) if params[:proposal][:retired_explanation].blank?
      @proposal.errors.empty?
    end

    def resource_model
      Proposal
    end

    def set_featured_proposal_votes(proposals)
      @featured_proposals_votes = current_user ? current_user.proposal_votes(proposals) : {}
    end

    def discard_archived
      @resources = @resources.not_archived unless @current_order == "archival_date"
    end

    def load_retired
      if params[:retired].present?
        @resources = @resources.retired
        @resources = @resources.where(retired_reason: params[:retired]) if Proposal::RETIRE_OPTIONS.include?(params[:retired])
      else
        @resources = @resources.not_retired
      end
    end

    def load_featured
      @featured_proposals = Proposal.not_archived.sort_by_confidence_score.limit(0) if (!@advanced_search_terms && @search_terms.blank? && @tag_filter.blank? && params[:retired].blank?)
      if @featured_proposals.present?
        set_featured_proposal_votes(@featured_proposals)
        @resources = @resources.where('proposals.id NOT IN (?)', @featured_proposals.map(&:id))
      end
    end

    def load_successful_proposals
      @proposal_successful_exists = Proposal.successful.exists?
    end

    # TODO:
    def load_municipality_proposals
      @proposal_municipality = Proposal.where(problem.user.administrator != nil)
    end

end
