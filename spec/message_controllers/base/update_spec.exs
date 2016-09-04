defmodule WokAsyncMessageHandler.MessageControllers.Base.UpdateSpec do
  use ESpec, async: false
  alias WokAsyncMessageHandler.Spec.Repo
  alias WokAsyncMessageHandler.Models.ConsumerMessageIndex
  alias WokAsyncMessageHandler.Models.StoppedPartition
  alias WokAsyncMessageHandler.MessageControllers.Base.Helpers
  alias WokAsyncMessageHandler.Helpers.TestMessage

  let! :from_bot, do: "from_bot"

  before do
    if( :ets.info(Helpers.ets_table) == :undefined ) do
      :ets.new(Helpers.ets_table, [:set, :public, :named_table])
    end
  end

  describe "#create", create: true do
    let! :payload, do: %{id: 1, topic: "create", partition: 1, message_id: 1224, error: "new error"}
    let! :event, do: TestMessage.build_event_message(payload, from_bot, 401)
    let! :from_service, do: "mybot"
    let! :cmi, do: Repo.insert!(%ConsumerMessageIndex{from: from_service, id_message: 1000})
    let! :event, do: TestMessage.build_event_message(payload, from_bot, 401)
    before do: allow(TestMessageController).to accept(:test_on_update_before_update)
    before do: allow(TestMessageController).to accept(:test_on_update_after_update)
    before do: {:shared, result: TestMessageController.create(event)}
    it do
      expect(shared.result).to eq(event)
      expect(StoppedPartition |> Repo.all |> List.first |> Map.take([:topic, :partition, :message_id, :error]))
      .to eq(%{error: "new error", message_id: 1224, partition: 1, topic: "create"})
      expect(TestMessageController).to accepted(:test_on_update_before_update, :any, count: 1)
      expect(TestMessageController).to accepted(:test_on_update_after_update, :any, count: 1)
    end
  end

  describe "#update", update: true do
    let! :cmi, do: Repo.insert!(%ConsumerMessageIndex{from: from_bot, id_message: 401})
    let! :payload, do: %{id: 12, topic: "topic bidon", partition: 1, message_id: 1224, error: "new error"}

    context "when message has already been processed" do
      let! :event, do: TestMessage.build_event_message(payload, from_bot, 401)

      before do: allow(Repo).to accept(:get, fn(module, id) ->
          case module do
            ConsumerMessageIndex -> passthrough([module, id])
            StoppedPartition -> passthrough([module, id])
          end
        end)
      context "with id_message fetched in DB" do
        before do: {:shared, result: TestMessageController.update(event)}
        it do: expect(shared.result).to eq(event)
        it do: expect(Repo.get(ConsumerMessageIndex, cmi.id).id_message).to eq(401)
        it do: expect(Repo).to accepted(:get, [StoppedPartition, 12], count: 0)
      end

      context "with id_message already in ets" do        
        before do: true = :ets.insert(:botsunit_wok_consumers_message_index, {from_bot, cmi})
        before do: allow(Repo).to accept(:one, fn(arg) -> passthrough([arg]) end)
        before do: {:shared, result: TestMessageController.update(event)}

        it do: expect(shared.result).to eq(event)
        it do: expect(Repo.get(ConsumerMessageIndex, cmi.id).id_message).to eq(401)
        it do: expect(Repo).to accepted(:one, :any, count: 0)
        it do: expect(Repo).to accepted(:get, [StoppedPartition, 12], count: 0)
      end
    end

    context "when message has not yet been processed" do
      let! :event, do: TestMessage.build_event_message(payload, from_bot, 402)
      context "with id_message already in ets" do
        before do: true = :ets.insert(:botsunit_wok_consumers_message_index, {from_bot, cmi})
        before do: allow(TestMessageController).to accept(:test_on_update_before_update)
        before do: allow(TestMessageController).to accept(:test_on_update_after_update)

        context "when insert in db is ok" do
          before do: {:shared, result: TestMessageController.update(event)}
          it do: expect(shared.result).to eq(event)
          it do: expect(ConsumerMessageIndex |> Repo.all |> Enum.count).to eq(1)
          it do: expect(StoppedPartition |> Repo.all |> Enum.count).to eq(1)
          it do: expect(StoppedPartition |> Repo.all |> List.first |> Map.take([:topic, :partition, :message_id, :error]))
                 .to eq(%{topic: "topic bidon", partition: 1, message_id: 1224, error: "new error"})
          it do: expect(TestMessageController).to accepted(:test_on_update_before_update, :any, count: 1)
          it do: expect(TestMessageController).to accepted(:test_on_update_after_update, :any, count: 1)
          it do: expect(Repo.get(ConsumerMessageIndex, cmi.id).id_message).to eq(402)
          it do: expect(:ets.lookup(:botsunit_wok_consumers_message_index, from_bot))
                 .to eq([{from_bot, Repo.get(ConsumerMessageIndex, cmi.id)}])
        end

        context "when using another field as id to find the message" do
          let! :stopped_partition, do: Repo.insert!(%StoppedPartition{topic: "pepito", partition: 999, message_id: 876, error: "original error"})
          let! :payload, do: %{id: 12, topic: "tropico", partition: 1, pmessage_id: 876, field_to_remap: "remaped error"}
          before do: {:shared, result: TestMessageControllerWithMasterKey.update(event)}
          it do: expect(shared.result).to eq(event)
          it do: expect(ConsumerMessageIndex |> Repo.all |> Enum.count).to eq(1)
          it do: expect(StoppedPartition |> Repo.all |> Enum.count).to eq(1)
          it do: expect(StoppedPartition |> Repo.all |> List.first |> Map.take([:topic, :partition, :message_id, :error]))
                 .to eq(%{error: "remaped error", message_id: 876, partition: 1, topic: "tropico"})
          it do: expect(Repo.get(ConsumerMessageIndex, cmi.id).id_message).to eq(402)
          it do: expect(:ets.lookup(:botsunit_wok_consumers_message_index, from_bot))
                 .to eq([{from_bot, Repo.get(ConsumerMessageIndex, cmi.id)}])
        end

        context "when error on insert in db" do
          let! :event, do: TestMessage.build_event_message(payload, from_bot, 402)
          before do: allow(Repo).to accept(:insert_or_update, fn(_) -> {:error, :ecto_changeset} end)
          before do
            exception = try do
              TestMessageController.update(event)
            rescue
              e -> e
            end
            {:shared, exception: exception}
          end

          it do: expect(ConsumerMessageIndex |> Repo.all |> Enum.count).to eq(1)
          it do: expect(StoppedPartition |> Repo.all |> Enum.count).to eq(0)
          it do: expect(TestMessageController).to accepted(:test_on_update_before_update, :any, count: 1)
          it do: expect(TestMessageController).to accepted(:test_on_update_after_update, :any, count: 0)
          it do: expect(Repo.get(ConsumerMessageIndex, cmi.id).id_message).to eq(401)
          it do: expect(:ets.lookup(:botsunit_wok_consumers_message_index, from_bot))
                 .to eq([{from_bot, Repo.get(ConsumerMessageIndex, cmi.id)}])
          it do: expect(String.match?(shared.exception.message, ~r/Wok Async Message Handler Exception @update$/))
        end

        context "when update_consumer_message_index fails" do
          let! :changeset, do: ConsumerMessageIndex.changeset(cmi, %{id_message: 99999})
          before do: allow(ConsumerMessageIndex).to accept(:changeset, fn(_cmi, %{id_message: 401}) -> changeset end)
          before do: allow(Repo).to accept(:update, fn(changeset) -> {:error, changeset} end)
          before do
            exception = try do
              TestMessageController.update(event)
            rescue
              e -> e
            end
            {:shared, changeset: changeset, exception: exception, fresh_cmi: Repo.get(ConsumerMessageIndex, cmi.id)}
          end              
          it do: expect(StoppedPartition |> Repo.all |> Enum.count ).to eq(0)
          it do: expect(shared.fresh_cmi.id_message).to eq(401)
          it do: expect(:ets.lookup(:botsunit_wok_consumers_message_index, from_bot))
                 .to eq([{from_bot, shared.fresh_cmi}])
          it do: expect(String.match?(shared.exception.message, ~r/Wok Async Message Handler Exception @update$/))
        end
      end
        

      context "wihtout any id_message in ets or db" do
        let! :event, do: TestMessage.build_event_message(payload, from_bot, 402)
        before do
          result = TestMessageController.update(event)
          {:shared, result: result, cmi: ConsumerMessageIndex |> Repo.all |> List.first, resource_created: StoppedPartition |> Repo.all |> List.first}
        end
        it do: expect(shared.resource_created |> Map.take([:topic, :partition, :message_id, :error]))
               .to eq(%{error: "new error", message_id: 1224, partition: 1, topic: "topic bidon"})
        it do: expect(shared.result).to eq(event)
        it do: expect(ConsumerMessageIndex |> Repo.all).to eq([shared.cmi])
        it do: expect(StoppedPartition |> Repo.all).to eq([shared.resource_created])
        it do: expect(Map.take shared.cmi, [:from, :id_message]).to eq(%{from: from_bot, id_message: 402})
        it do: expect(:ets.lookup(:botsunit_wok_consumers_message_index, from_bot))
                     .to eq([{from_bot, shared.cmi}])
      end
    end
  end
end