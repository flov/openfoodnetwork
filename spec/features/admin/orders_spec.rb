require "spec_helper"

feature %q{
    As an administrator
    I want to manage orders
} do
  include AuthenticationWorkflow
  include WebHelper

  background do
    @user = create(:user)
    @product = create(:simple_product)
    @distributor = create(:distributor_enterprise, charges_sales_tax: true)
    @order_cycle = create(:simple_order_cycle, name: 'One', distributors: [@distributor], variants: [@product.variants.first])

    @order = create(:order_with_totals_and_distribution, user: @user, distributor: @distributor, order_cycle: @order_cycle, state: 'complete', payment_state: 'balance_due')

    # ensure order has a payment to capture
    @order.finalize!

    create :check_payment, order: @order, amount: @order.total
  end

  scenario "creating an order with distributor and order cycle", js: true, retry: 3 do
    distributor_disabled = create(:distributor_enterprise)
    create(:simple_order_cycle, name: 'Two')

    login_to_admin_section

    visit '/admin/orders'
    click_link 'New Order'

    # Distributors without an order cycle should be shown as disabled
    page.should have_selector "option[value='#{distributor_disabled.id}'][disabled='disabled']"

    # When we select a distributor, it should limit order cycle selection to those for that distributor
    page.should_not have_select 'order_order_cycle_id'
    select @distributor.name, from: 'order_distributor_id'
    page.should have_select 'order_order_cycle_id', options: ['', 'One']
    select @order_cycle.name, from: 'order_order_cycle_id'

    page.should have_content 'ADD PRODUCT'
    targetted_select2_search @product.name, from: '#add_variant_id', dropdown_css: '.select2-drop'
    click_link 'Add'
    page.has_selector? "table.index tbody[data-hook='admin_order_form_line_items'] tr"  # Wait for JS
    page.should have_selector 'td', text: @product.name

    click_button 'Update'

    page.should have_selector 'h1', text: 'Customer Details'
    o = Spree::Order.last
    o.distributor.should == @distributor
    o.order_cycle.should == @order_cycle
  end

  scenario "can add a product to an existing order", js: true, retry: 3 do
    login_to_admin_section
    visit '/admin/orders'

    click_edit

    targetted_select2_search @product.name, from: '#add_variant_id', dropdown_css: '.select2-drop'

    click_link 'Add'

    page.should have_selector 'td', text: @product.name
    @order.line_items(true).map(&:product).should include @product
  end

  scenario "can't add products to an order outside the order's hub and order cycle", js: true do
    product = create(:simple_product)

    login_to_admin_section
    visit '/admin/orders'
    page.find('td.actions a.icon-edit').click

    page.should_not have_select2_option product.name, from: ".variant_autocomplete", dropdown_css: ".select2-search"
  end

  scenario "can't change distributor or order cycle once order has been finalized" do
    @order.update_attributes order_cycle_id: nil

    login_to_admin_section
    visit '/admin/orders'
    page.find('td.actions a.icon-edit').click

    page.should have_no_select 'order_distributor_id'
    page.should have_no_select 'order_order_cycle_id'

    page.should have_selector 'p', text: "Distributor: #{@order.distributor.name}"
    page.should have_selector 'p', text: "Order cycle: None"
  end

  scenario "capture multiple payments from the orders index page" do
    # d.cook: could also test for an order that has had payment voided, then a new check payment created but not yet captured. But it's not critical and I know it works anyway.

    login_to_admin_section

    visit '/admin/orders'
    current_path.should == spree.admin_orders_path

    # click the 'capture' link for the order
    page.find("[data-action=capture][href*=#{@order.number}]").click

    page.should have_content "Payment Updated"

    # check the order was captured
    @order.reload
    @order.payment_state.should == "paid"

    # we should still be on the same page
    current_path.should == spree.admin_orders_path
  end


  context "as an enterprise manager" do
    let(:coordinator1) { create(:distributor_enterprise) }
    let(:coordinator2) { create(:distributor_enterprise) }
    let!(:order_cycle1) { create(:order_cycle, coordinator: coordinator1) }
    let!(:order_cycle2) { create(:simple_order_cycle, coordinator: coordinator2) }
    let!(:supplier1) { order_cycle1.suppliers.first }
    let!(:supplier2) { order_cycle1.suppliers.last }
    let!(:distributor1) { order_cycle1.distributors.first }
    let!(:distributor2) { order_cycle1.distributors.reject{ |d| d == distributor1 }.last } # ensure d1 != d2
    let(:product) { order_cycle1.products.first }

    before(:each) do
      @enterprise_user = create_enterprise_user
      @enterprise_user.enterprise_roles.build(enterprise: supplier1).save
      @enterprise_user.enterprise_roles.build(enterprise: coordinator1).save
      @enterprise_user.enterprise_roles.build(enterprise: distributor1).save

      login_to_admin_as @enterprise_user
    end

    scenario "creating an order with distributor and order cycle", js: true do
      visit '/admin/orders'
      click_link 'New Order'

      select distributor1.name, from: 'order_distributor_id'
      select order_cycle1.name, from: 'order_order_cycle_id'

      expect(page).to have_content 'ADD PRODUCT'
      targetted_select2_search product.name, from: '#add_variant_id', dropdown_css: '.select2-drop'

      click_link 'Add'
      page.has_selector? "table.index tbody[data-hook='admin_order_form_line_items'] tr"  # Wait for JS
      expect(page).to have_selector 'td', text: product.name

      expect(page).to have_select 'order_distributor_id', with_options: [distributor1.name]
      expect(page).to_not have_select 'order_distributor_id', with_options: [distributor2.name]

      expect(page).to have_select 'order_order_cycle_id', with_options: [order_cycle1.name]
      expect(page).to_not have_select 'order_order_cycle_id', with_options: [order_cycle2.name]

      click_button 'Update'

      expect(page).to have_selector 'h1', text: 'Customer Details'
      o = Spree::Order.last
      expect(o.distributor).to eq distributor1
      expect(o.order_cycle).to eq order_cycle1
    end

  end

  # Working around intermittent click failing
  # Possible causes of failure:
  #  - the link moves
  #  - the missing content (font icon only)
  #  - the screen is not big enough
  # However, some operations before the click or a second click on failure work.
  #
  # A lot of people had similar problems:
  # https://github.com/teampoltergeist/poltergeist/issues/520
  # https://github.com/thoughtbot/capybara-webkit/issues/494
  def click_edit
    click_result = click_icon :edit
    unless click_result['status'] == 'success'
      click_icon :edit
    end
  end
end
