Rails.application.routes.draw do
  mount Rswag::Ui::Engine => '/docs'
  mount Rswag::Api::Engine => '/docs'
  
  mount PgHero::Engine, at: "pghero"

  namespace :api, :defaults => {:format => :json} do
    namespace :v1 do
      resources :hosts, constraints: { id: /.*/ }, only: [:index, :show] do
        resources :repositories, constraints: { id: /.*/ }, only: [:index, :show]
      end
    end
  end

  resources :hosts, constraints: { id: /.*/ }, only: [:index, :show], :defaults => {:format => :html} do
    resources :repositories, constraints: { id: /.*/ }, only: [:index, :show]
    resources :owners, constraints: { id: /.*/ }, only: [:index, :show]
  end

  resources :exports, only: [:index], path: 'open-data'

  get '/404', to: 'errors#not_found'
  get '/422', to: 'errors#unprocessable'
  get '/500', to: 'errors#internal'

  root "repositories#index"
end
