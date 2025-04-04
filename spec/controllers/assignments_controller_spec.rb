# frozen_string_literal: true

require 'rails_helper'

describe AssignmentsController, type: :request do
  let(:slug_params) { 'Wikipedia_Fellows/Basket-weaving_fellows_(summer_2018)' }
  let!(:course) { create(:course, id: 1, submitted: true, slug: slug_params) }
  let!(:user) { create(:user) }

  before do
    stub_wiki_validation
    course.campaigns << Campaign.first
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
  end

  describe 'DELETE #destroy' do
    context 'when the user owns the assignment' do
      let(:assignment) do
        create(:assignment, course_id: course.id, user_id: user.id,
                            article_title: 'Selfie', role: 0)
      end

      before do
        expect_any_instance_of(WikiCourseEdits).to receive(:remove_assignment)
        expect_any_instance_of(WikiCourseEdits).to receive(:update_assignments)
        expect_any_instance_of(WikiCourseEdits).to receive(:update_course)
      end

      context 'when the assignment_id is provided' do
        let(:params) { { course_slug: course.slug } }

        before do
          delete "/assignments/#{assignment.id}", params: { id: assignment.id }.merge(params)
        end

        it 'destroys the assignment' do
          expect(Assignment.count).to eq(0)
        end

        it 'renders a json response' do
          expect(response.body).to eq({ assignmentId: assignment.id }.to_json)
        end
      end

      context 'when the assignment_id is not provided' do
        let(:params) do
          { course_slug: course.slug, user_id: user.id,
            article_title: assignment.article_title, role: assignment.role }
        end

        before do
          delete "/assignments/#{assignment.id}", params: { id: 'undefined' }.merge(params)
        end
        # This happens when an assignment is deleted right after it has been created.
        # The React frontend will not have an assignment_id until
        # it gets refreshed from the server.

        it 'deletes the assignment' do
          expect(Assignment.count).to eq(0)
        end
      end
    end

    # This test case checks behavior when the article is marked as an available article,
    # indicated by the assignment's flags having `available_article: true`.
    context 'when the article is marked as an available article' do
      let(:assignment) do
        create(:assignment, course_id: course.id, user_id: user.id,
                           flags: { available_article: true })
      end

      before do
        create(:courses_user, course:, user:)
      end

      context 'when the assignment_id is provided' do
        let(:params) do
          { course_slug: course.slug, assignment_id: assignment.id,
          user_id: user.id, format: :json }
        end

        before do
          delete "/assignments/#{assignment.id}", params: { id: assignment.id }.merge(params)
        end

        it 'unclaims the assignment' do
          expect(assignment.reload.user_id).to be_nil
        end
      end

      context 'when the assignment_id is not provided' do
        let(:params) do
          { course_slug: course.slug, user_id: user.id, assignment_id: assignment.id,
            article_title: assignment.article_title, role: assignment.role,
             format: :json }
        end

        before do
          delete "/assignments/#{assignment.id}", params: { id: 'undefined' }.merge(params)
        end

        it 'unclaims the assignment' do
          expect(assignment.reload.user_id).to be_nil
        end
      end

      context 'when the user does not have permission to unclaim the assignment' do
        let(:params) do
          { course_slug: course.slug, format: :json }
        end

        let!(:assignment) do
          create(:assignment, course_id: course.id, user_id: user.id + 1)
        end

        before do
          delete "/assignments/#{assignment.id}", params: { id: assignment.id }.merge(params)
        end

        it 'does not allow the assignment to be unclaimed' do
          expect(response.status).to eq(401)
        end
      end
    end

    context 'when the user does not have permission do destroy the assignment' do
      let(:assignment) { create(:assignment, course_id: course.id, user_id: user.id + 1) }
      let(:params) { { course_slug: course.slug } }

      before do
        delete "/assignments/#{assignment.id}", params: { id: assignment }.merge(params)
      end

      it 'does not destroy the assignment' do
        expect(Assignment.count).to eq(1)
      end

      it 'renders a 401 status' do
        expect(response.status).to eq(401)
      end
    end

    context 'when parameters for a non-existent assignment are provided' do
      let(:assignment) { create(:assignment, course_id: course.id, user_id: user.id) }
      let(:params) do
        { course_slug: course.slug, user_id: user.id + 1,
          article_title: assignment.article_title, role: assignment.role }
      end

      before do
        delete "/assignments/#{/undefined/}", params: { id: 'undefined' }.merge(params)
      end
      # This happens when an assignment is deleted right after it has been created.
      # The React frontend will not will not have an assignment_id until
      # it gets refreshed from the server.

      it 'renders a 404' do
        expect(response.status).to eq(404)
      end
    end
  end

  describe 'POST #create' do
    context 'when the user has permission to create the assignment' do
      let(:course) do
        create(:course, slug: 'Unasp/Teorias_da_Comunicação_(term_1)', submitted: true)
      end
      let(:assignment_params) do
        { user_id: user.id, course_slug: course.slug, title: 'jalapeño', role: 0, format: :json }
      end

      context 'when the article does not exist' do
        it 'imports the article and associates it with the assignment' do
          expect(Article.find_by(title: 'Jalapeño')).to be_nil

          VCR.use_cassette 'assignment_import' do
            expect_any_instance_of(WikiCourseEdits).to receive(:update_assignments)
            expect_any_instance_of(WikiCourseEdits).to receive(:update_course)
            post '/assignments', params: assignment_params
            assignment = assigns(:assignment)
            expect(assignment).to be_a_kind_of(Assignment)
            expect(assignment.article.title).to eq('Jalapeño')
            expect(assignment.article.namespace).to eq(Article::Namespaces::MAINSPACE)
            expect(assignment.article.rating).not_to be_nil
            expect(assignment.article.updated_at).not_to be_nil
          end
        end
      end

      context 'when adding an article to the list of available articles' do
        let(:assignment_params) do
          { course_slug: course.slug, title: 'jalapeño', role: 0, format: :json }
        end

        before do
          # Creates an association between the user and the course as an instructor
          create(:courses_user, course:, user:, role: CoursesUsers::Roles::INSTRUCTOR_ROLE)
        end

        it 'creates the assignment and marks the article as available' do
          expect(Article.find_by(title: 'Jalapeño')).to be_nil

          VCR.use_cassette 'assignment_import' do
            expect_any_instance_of(WikiCourseEdits).to receive(:update_assignments)
            expect_any_instance_of(WikiCourseEdits).to receive(:update_course)
            post '/assignments', params: assignment_params
            assignment = assigns(:assignment)
            expect(assignment).to be_a_kind_of(Assignment)
            expect(assignment.article.title).to eq('Jalapeño')
            expect(assignment.user_id).to be_nil # Ensure the assignment is not claimed by the user
            expect(assignment.flags[:available_article])
              .to eq(true) # Ensure the article is marked as available
          end
        end
      end

      context 'when the assignment is for Wiktionary' do
        let!(:en_wiktionary) { create(:wiki, language: 'en', project: 'wiktionary') }
        let(:wiktionary_params) do
          { user_id: user.id, course_slug: course.slug, title: 'selfie', role: 0,
            language: 'en', project: 'wiktionary', format: :json }
        end

        it 'imports the article with a lower-case title' do
          expect(Article.find_by(title: 'selfie')).to be_nil

          VCR.use_cassette 'assignment_import' do
            expect_any_instance_of(WikiCourseEdits).to receive(:update_assignments)
            expect_any_instance_of(WikiCourseEdits).to receive(:update_course)
            post '/assignments', params: wiktionary_params
            assignment = assigns(:assignment)
            expect(assignment).to be_a_kind_of(Assignment)
            expect(assignment.article.title).to eq('selfie')
            expect(assignment.article.namespace).to eq(Article::Namespaces::MAINSPACE)
          end
        end
      end

      context 'when the assignment is for Wikisource' do
        let!(:www_wikisource) { create(:wiki, language: 'www', project: 'wikisource') }
        let(:wikisource_params) do
          { user_id: user.id, course_slug: course.slug, title: 'Heyder Cansa', role: 0,
            language: 'www', project: 'wikisource', format: :json }
        end

        before do
          expect(Article.find_by(title: 'Heyder Cansa')).to be_nil
        end

        it 'imports the article' do
          VCR.use_cassette 'assignment_import' do
            expect_any_instance_of(WikiCourseEdits).to receive(:update_assignments)
            expect_any_instance_of(WikiCourseEdits).to receive(:update_course)
            post '/assignments', params: wikisource_params
            assignment = assigns(:assignment)
            expect(assignment).to be_a_kind_of(Assignment)
            expect(assignment.article.title).to eq('Heyder_Cansa')
            expect(assignment.article.namespace).to eq(Article::Namespaces::MAINSPACE)
          end
        end
      end

      context 'when the assignment is for Wikimedia incubator' do
        let!(:wikimedia_incubator) { create(:wiki, language: 'incubator', project: 'wikimedia') }
        let(:wikimedia_params) do
          { user_id: user.id, course_slug: course.slug, title: 'Wp/kiu/Heyder Cansa', role: 0,
            language: 'incubator', project: 'wikimedia', format: :json }
        end

        before do
          expect(Article.find_by(title: 'Wp/kiu/Heyder Cansa')).to be_nil
        end

        it 'imports the article' do
          VCR.use_cassette 'assignment_import' do
            expect_any_instance_of(WikiCourseEdits).to receive(:update_assignments)
            expect_any_instance_of(WikiCourseEdits).to receive(:update_course)
            post '/assignments', params: wikimedia_params
            assignment = assigns(:assignment)
            expect(assignment).to be_a_kind_of(Assignment)
            expect(assignment.article.title).to eq('Wp/kiu/Heyder_Cansa')
            expect(assignment.article.namespace).to eq(Article::Namespaces::MAINSPACE)
          end
        end
      end

      context 'when the article exists' do
        let(:assignment_params_with_language_and_project) do
          { user_id: user.id, course_slug: course.slug, title: 'pizza',
            role: 0, language: 'es', project: 'wikibooks', format: :json }
        end

        before do
          create(:article, title: 'Pizza', namespace: Article::Namespaces::MAINSPACE)
          create(:article, title: 'Pizza', wiki_id: es_wikibooks.id,
                           namespace: Article::Namespaces::MAINSPACE)
        end

        let(:es_wikibooks) { create(:wiki, language: 'es', project: 'wikibooks') }

        it 'sets assignments ivar with a default wiki' do
          expect_any_instance_of(WikiCourseEdits).to receive(:update_assignments)
          expect_any_instance_of(WikiCourseEdits).to receive(:update_course)
          VCR.use_cassette 'assignment_import' do
            post '/assignments', params: assignment_params
            assignment = assigns(:assignment)
            expect(assignment).to be_a_kind_of(Assignment)
            expect(assignment.wiki.language).to eq('en')
            expect(assignment.wiki.project).to eq('wikipedia')
          end
        end

        it 'renders a json response' do
          expect_any_instance_of(WikiCourseEdits).to receive(:update_assignments)
          expect_any_instance_of(WikiCourseEdits).to receive(:update_course)
          VCR.use_cassette 'assignment_import' do
            post '/assignments', params: assignment_params
          end
          json_response = Oj.load(response.body)

          # response makes created_at differ by milliseconds, which is weird,
          # so test attrs that actually matter rather than whole record
          expect(json_response['article_title'])
            .to eq(Assignment.last.article_title)
          expect(json_response['user_id']).to eq(Assignment.last.user_id)
          expect(json_response['role']).to eq(Assignment.last.role)
        end

        it 'sets the wiki based on language and project params' do
          expect_any_instance_of(WikiCourseEdits).to receive(:update_assignments)
          expect_any_instance_of(WikiCourseEdits).to receive(:update_course)
          post '/assignments', params: assignment_params_with_language_and_project
          assignment = assigns(:assignment)
          expect(assignment).to be_a_kind_of(Assignment)
          expect(assignment.wiki_id).to eq(es_wikibooks.id)
        end
      end
    end

    context 'when the user does not have permission to create the assignment' do
      let(:course) { create(:course) }
      let(:assignment_params) do
        { user_id: user.id + 1, course_slug: course.slug, title: 'pizza', role: 0 }
      end

      before do
        post '/assignments', params: assignment_params
      end

      it 'does not create the assignment' do
        expect(Assignment.count).to eq(0)
      end

      it 'renders a 401 status' do
        expect(response.status).to eq(401)
      end
    end

    context 'when the wiki params are not valid' do
      let(:course) { create(:course) }
      let(:invalid_wiki_params) do
        { user_id: user.id, course_slug: course.slug, title: 'Pikachu', role: 0,
          language: 'en', project: 'bulbapedia', format: :json }
      end
      let(:subject) do
        post '/assignments', params: invalid_wiki_params
      end

      it 'returns a 404 error message' do
        subject
        expect(response.body).to include('Invalid assignment')
        expect(response.status).to eq(404)
      end
    end

    context 'when the same assignment already exists' do
      let(:title) { 'My article' }
      let!(:assignment) do
        create(:assignment, course_id: course.id, user_id: user.id, role: 0, article_title: title)
      end
      let(:duplicate_assignment_params) do
        { user_id: user.id, course_slug: course.slug, title:, role: 0, format: :json }
      end

      before do
        VCR.use_cassette 'assignment_import' do
          post '/assignments', params: duplicate_assignment_params
        end
      end

      it 'renders an error message with the article title' do
        expect(response.status).to eq(500)
        expect(response.body).to include('My_article')
      end
    end

    context 'when the title is invalid' do
      let(:title) { 'My [invalid] title' }
      let(:invalid_assignment_params) do
        { user_id: user.id, course_slug: course.slug, title:, role: 0, format: :json }
      end

      before do
        VCR.use_cassette 'assignment_import' do
          post '/assignments', params: invalid_assignment_params
        end
      end

      it 'renders an error message with the article title' do
        expect(response.status).to eq(500)
        expect(response.body).to include('not a valid article title')
      end
    end

    context 'when a case-variant of the assignment already exists' do
      let(:title) { 'My article' }
      let(:variant_title) { 'MY ARTICLE' }
      let!(:assignment) do
        create(:assignment, course_id: course.id, user_id: user.id, role: 0, article_title: title)
      end
      let(:case_variant_assignment_params) do
        { user_id: user.id, course_slug: course.slug, title: variant_title, role: 0, format: :json }
      end

      before do
        expect_any_instance_of(WikiCourseEdits).to receive(:update_assignments)
        expect_any_instance_of(WikiCourseEdits).to receive(:update_course)
        VCR.use_cassette 'assignment_import' do
          post '/assignments', params: case_variant_assignment_params
        end
      end

      it 'creates the case-variant assignment' do
        expect(response.status).to eq(200)
        expect(Assignment.last.article_title).to eq('MY_ARTICLE')
      end
    end
  end

  describe 'PUT #claim' do
    let(:assignment) { create(:assignment, course_id: course.id, role: 0) }
    let(:request_params) do
      { course_id: course.id, id: assignment.id, user_id: user.id, format: :json }
    end

    context 'when the claim succeeds' do
      before { create(:courses_user, course:, user:) }

      it 'renders a 200 and the assignment belongs to the user' do
        put "/assignments/#{assignment.id}/claim", params: request_params
        expect(response.status).to eq(200)
        expect(assignment.reload.user_id).to eq(user.id)
      end
    end

    context 'when the assignment was already claimed by another user' do
      before { create(:courses_user, course:, user:) }

      it 'renders a 409' do
        assignment.update(user_id: 1)
        put "/assignments/#{assignment.id}/claim", params: request_params
        expect(response.status).to eq(409)
      end
    end

    context 'when the same article is already assigned to the user' do
      before do
        create(:courses_user, course:, user:)
        create(:assignment, article_title: assignment.article_title, user:,
                            course:, role: assignment.role)
        expect_any_instance_of(Course).to receive(:retain_available_articles?).and_return(true)
      end

      it 'renders a 409' do
        put "/assignments/#{assignment.id}/claim", params: request_params
        expect(response.status).to eq(409)
      end
    end

    context 'when the user is not in the course' do
      it 'renders a 401' do
        put "/assignments/#{assignment.id}/claim", params: request_params
        expect(response.status).to eq(401)
      end
    end

    context 'when the course is set to retain available articles' do
      before do
        create(:courses_user, course:, user:)
        allow_any_instance_of(Course).to receive(:retain_available_articles?).and_return(true)
      end

      it 'creates a new assignment and keeps the available one' do
        put "/assignments/#{assignment.id}/claim", params: request_params
        expect(response.status).to eq(200)
        expect(assignment.reload.user_id).to be_nil
        expect(user.assignments.first.article_title).to eq(assignment.article_title)
      end
    end
  end

  describe 'PATCH #update_status' do
    let(:assignment) { create(:assignment, course:, role: 0) }
    let(:request_params) do
      { course_id: course.id, id: assignment.id, user_id: user.id, format: :json, status: }
    end

    context 'when a status param is provided' do
      let(:status) { 'in_progress' }

      it 'renders a 200' do
        patch "/assignments/#{assignment.id}/status", params: request_params
        expect(response.status).to eq(200)
        expect(assignment.reload.status).to eq(status)
      end
    end

    context 'when no status param is provided' do
      let(:status) { nil }

      it 'renders a 422' do
        patch "/assignments/#{assignment.id}/status", params: request_params
        expect(response.status).to eq(422)
      end
    end
  end

  describe 'PATCH #update_sanbox_url' do
    let!(:assignment) { create(:assignment, course:, user_id: user.id, role: 0) }
    let!(:base_url) { "https://#{assignment.wiki.language}.#{assignment.wiki.project}.org/wiki" }
    let(:test_user) { create(:user, username: 'testUser') }
    let(:existing_sandbox_url) { assignment.sandbox_url }
    let(:new_username) { test_user.username }

    context 'updating sandbox url with valid urls' do
      let(:preferred_sandbox_url) { "#{base_url}/User:#{new_username}/testingArticle" }
      let!(:request_params) do
        { id: assignment.id, user_id: user.id, newUrl: preferred_sandbox_url, format: :json,
course_slug: course.slug }
      end

      it 'update sandbox url successfully with example 1' do
        patch "/assignments/#{assignment.id}/update_sandbox_url",
              params: request_params

        expect(assignment.reload.sandbox_url).to eq(preferred_sandbox_url)
      end

      it 'update sandbox url successfully with example 2' do
        preferred_sandbox_url = "#{base_url}/User:#{new_username}/Any_Article!@$%^&*()_+\`~"
        request_params[:newUrl] = preferred_sandbox_url
        patch "/assignments/#{assignment.id}/update_sandbox_url",
              params: request_params

        expect(assignment.reload.sandbox_url).to eq(preferred_sandbox_url)
      end
    end

    context 'updating sandbox url with valid format but belongs to different wiki' do
      let(:preferred_sandbox_url) { "https://www.wikipedia.org/wiki/User:#{new_username}/testingArticle" }
      let!(:request_params) do
        { id: assignment.id, user_id: user.id, newUrl: preferred_sandbox_url, format: :json,
course_slug: course.slug }
      end

      it 'does not update url and send response with status: unprocessable entity' do
        patch "/assignments/#{assignment.id}/update_sandbox_url",
              params: request_params

        expect(assignment.reload.sandbox_url).to eq(existing_sandbox_url)
        expect(response.status).to eq(422)
      end
    end

    context 'updating sandbox url with invalid url format' do
      let(:preferred_sandbox_url) { 'anyGebberishURL' }
      let!(:request_params) do
        { id: assignment.id, user_id: user.id, newUrl: preferred_sandbox_url, format: :json,
course_slug: course.slug }
      end

      it 'does not update url and send response with status: bad request example 1' do
        patch "/assignments/#{assignment.id}/update_sandbox_url",
              params: request_params

        expect(assignment.reload.sandbox_url).to eq(existing_sandbox_url)
        expect(response.status).to eq(400)
      end

      it 'does not update url and send response with status: bad request example 2' do
        preferred_sandbox_url = "#{base_url}/#{new_username}/Article_name"
        request_params[:newUrl] = preferred_sandbox_url
        patch "/assignments/#{assignment.id}/update_sandbox_url",
              params: request_params

        expect(assignment.reload.sandbox_url).to eq(existing_sandbox_url)
        expect(response.status).to eq(400)
      end
    end
  end
end
