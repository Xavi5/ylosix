require 'test_helper'

class SearchesControllerTest < ActionController::TestCase
  test 'should get index' do
    get :index, query_text: 'camera'
    assert_response :success

    assert assigns(:variables)

    variables = assigns(:variables)
    assert variables['products'].any?
  end

  test 'should get index and visible' do
    product = products(:camera)
    product.update_attributes(visible: false)

    get :index, query_text: 'camera'
    assert_response :success

    assert assigns(:variables)

    variables = assigns(:variables)
    names = variables['products'].map { |obj| obj['name'] }
    assert !names.include?(product.name)
  end
end
