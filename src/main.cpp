#include "PCH.h"

#if defined(HAS_DIII_API) && HAS_DIII_API
#include "DIII_API.h"
#endif

namespace
{
    void InitializeLog()
    {
        const auto logDir = SKSE::log::log_directory();
        if (!logDir)
        {
            std::terminate();
        }

        const auto pluginName = SKSE::PluginDeclaration::GetSingleton()->GetName();
        const auto logPath = *logDir / fmt::format("{}.log", pluginName);

        auto sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(logPath.string(), true);
        auto log = std::make_shared<spdlog::logger>("global", std::move(sink));

        spdlog::set_default_logger(std::move(log));
        spdlog::set_level(spdlog::level::info);
        spdlog::flush_on(spdlog::level::info);
    }

#if defined(HAS_DIII_API) && HAS_DIII_API
    RE::SpellItem *GetTaughtSpell(RE::InventoryEntryData *entry)
    {
        if (!entry)
        {
            return nullptr;
        }

        auto *book = entry->GetObject() ? entry->GetObject()->As<RE::TESObjectBOOK>() : nullptr;
        if (!book || !book->TeachesSpell())
        {
            return nullptr;
        }

        return book->GetSpell();
    }

    bool IsKnownSpellTome(RE::InventoryEntryData *entry)
    {
        auto *taughtSpell = GetTaughtSpell(entry);
        auto *player = RE::PlayerCharacter::GetSingleton();
        if (!taughtSpell || !player)
        {
            return false;
        }

        return player->HasSpell(taughtSpell);
    }

    class KnownSpellTomeCondition final : public DIII::ICondition
    {
    public:
        explicit KnownSpellTomeCondition(bool expected) : _expected(expected) {}

        bool Match(RE::InventoryEntryData *entry) const override
        {
            if (!GetTaughtSpell(entry))
            {
                return false;
            }

            return IsKnownSpellTome(entry) == _expected;
        }

    private:
        bool _expected;
    };

    bool RegisterKnownSpellCondition(DIII::IAPI *api, const char *name)
    {
        const bool registered = api->RegisterCondition(
            name,
            [name](const Json::Value &value, RE::FormType type) -> std::unique_ptr<DIII::ICondition>
            {
                if (type != RE::FormType::Book)
                {
                    logger::warn("{} should only be used for Book entries, got form type {}", name, static_cast<std::uint32_t>(type));
                }

                if (!value.isBool())
                {
                    logger::warn("{} expects boolean JSON value", name);
                    return nullptr;
                }

                logger::info("{} condition builder accepted value={}", name, value.asBool());
                return std::make_unique<KnownSpellTomeCondition>(value.asBool());
            });

        logger::info("{} registration {}", name, registered ? "succeeded" : "failed");
        return registered;
    }

    void OnDIIIRegistration(SKSE::MessagingInterface::Message *message)
    {
        if (!message || message->type != DIII::kMessage_GetAPI || !message->data)
        {
            return;
        }

        auto *api = static_cast<DIII::IAPI *>(message->data);
        if (api->GetVersion() < 1)
        {
            logger::warn("DIII API version {} is unsupported", api->GetVersion());
            return;
        }

        logger::info("Connected to DIII API v{}", api->GetVersion());
        RegisterKnownSpellCondition(api, "knownSpellTome");
        RegisterKnownSpellCondition(api, "teachesKnownSpell");
    }
#endif
}

SKSEPluginLoad(const SKSE::LoadInterface *skse)
{
    InitializeLog();
    logger::info("inventory_injector_known_spells_skse init start");

    SKSE::Init(skse);
    logger::info("SKSE initialized");

#if defined(HAS_DIII_API) && HAS_DIII_API
    DIII::ListenForRegistration(OnDIIIRegistration);
    logger::info("DIII registration listener enabled");
#else
    logger::warn("DIII_API.h not found; skipping DIII integration (add external/diii/DIII_API.h)");
#endif

    logger::info("inventory_injector_known_spells_skse ready");
    return true;
}
