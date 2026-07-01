/*
 * This file is part of the AzerothCore Project. See AUTHORS file for Copyright information
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#include "AllItemScript.h"
#include "ItemScript.h"
#include "ScriptMgr.h"
#include "ScriptMgrMacros.h"
#include "ScriptedGossip.h"

bool ScriptMgr::OnQuestAccept(Player* player, Item* item, Quest const* quest)
{
    ASSERT(player);
    ASSERT(item);
    ASSERT(quest);

    auto ret = IsValidBoolScript<AllItemScript>([&](AllItemScript* script)
    {
        return !script->CanItemQuestAccept(player, item, quest);
    });

    if (ret && *ret)
    {
        return false;
    }

    auto tempScript = ScriptRegistry<ItemScript>::GetScriptById(item->GetScriptId());
    ClearGossipMenuFor(player);
    return tempScript ? tempScript->OnQuestAccept(player, item, quest) : false;
}

bool ScriptMgr::OnItemUse(Player* player, Item* item, SpellCastTargets const& targets)
{
    ASSERT(player);
    ASSERT(item);

    auto ret = IsValidBoolScript<AllItemScript>([&](AllItemScript* script)
    {
        return script->CanItemUse(player, item, targets);
    });

    if (ret && *ret)
    {
        return true;
    }

    auto tempScript = ScriptRegistry<ItemScript>::GetScriptById(item->GetScriptId());
    return tempScript ? tempScript->OnUse(player, item, targets) : false;
}

bool ScriptMgr::OnItemExpire(Player* player, ItemTemplate const* proto)
{
    ASSERT(player);
    ASSERT(proto);

    auto ret = IsValidBoolScript<AllItemScript>([&](AllItemScript* script)
    {
        return !script->CanItemExpire(player, proto);
    });

    if (ret && *ret)
    {
        return false;
    }

    auto tempScript = ScriptRegistry<ItemScript>::GetScriptById(proto->ScriptId);
    return tempScript ? tempScript->OnExpire(player, proto) : false;
}

bool ScriptMgr::OnItemRemove(Player* player, Item* item)
{
    ASSERT(player);
    ASSERT(item);

    auto ret = IsValidBoolScript<AllItemScript>([&](AllItemScript* script)
    {
        return !script->CanItemRemove(player, item);
    });

    if (ret && *ret)
    {
        return false;
    }

    auto tempScript = ScriptRegistry<ItemScript>::GetScriptById(item->GetScriptId());
    return tempScript ? tempScript->OnRemove(player, item) : false;
}

bool ScriptMgr::OnCastItemCombatSpell(Player* player, Unit* victim, SpellInfo const* spellInfo, Item* item)
{
    ASSERT(player);
    ASSERT(victim);
    ASSERT(spellInfo);
    ASSERT(item);

    auto tempScript = ScriptRegistry<ItemScript>::GetScriptById(item->GetScriptId());
    return tempScript ? tempScript->OnCastItemCombatSpell(player, victim, spellInfo, item) : true;
}

void ScriptMgr::OnGossipSelect(Player* player, Item* item, uint32 sender, uint32 action)
{
    ASSERT(player);
    ASSERT(item);

    ExecuteScript<AllItemScript>([&](AllItemScript* script)
    {
        script->OnItemGossipSelect(player, item, sender, action);
    });

    if (auto tempScript = ScriptRegistry<ItemScript>::GetScriptById(item->GetScriptId()))
    {
        tempScript->OnGossipSelect(player, item, sender, action);
    }
}

void ScriptMgr::OnGossipSelectCode(Player* player, Item* item, uint32 sender, uint32 action, const char* code)
{
    ASSERT(player);
    ASSERT(item);

    ExecuteScript<AllItemScript>([&](AllItemScript* script)
    {
        script->OnItemGossipSelectCode(player, item, sender, action, code);
    });

    if (auto tempScript = ScriptRegistry<ItemScript>::GetScriptById(item->GetScriptId()))
    {
        tempScript->OnGossipSelectCode(player, item, sender, action, code);
    }
}

// mod-custom-items: rewrite the on-wire entry for items in update packets.
void ScriptMgr::OnItemBuildValuesUpdate(Item const* item, uint32& entry)
{
    ExecuteScript<AllItemScript>([&](AllItemScript* script)
    {
        script->OnItemBuildValuesUpdate(item, entry);
    });
}

// mod-custom-items: substitute the ItemTemplate served on
// SMSG_ITEM_QUERY_SINGLE_RESPONSE based on the querier's session.
void ScriptMgr::OnItemQueryTemplate(Player const* querier, uint32 wireEntry, ItemTemplate const*& proto)
{
    ExecuteScript<AllItemScript>([&](AllItemScript* script)
    {
        script->OnItemQueryTemplate(querier, wireEntry, proto);
    });
}

// mod-custom-items: encapsulated per-field egress dispatch. Lives here
// rather than as a member of Object so the Object class stays untouched
// at the .h level and Object::BuildValuesUpdate only sees a one-line
// call-site modification. The two index ranges this routes through
// OnItemBuildValuesUpdate are:
//   * OBJECT_FIELD_ENTRY (offset 3) on Item-typed objects — drives the
//     bag-slot icon and on-cursor display lookups via Item.dbc.
//   * PLAYER_VISIBLE_ITEM_N_ENTRYID (N=1..19) on Player-typed objects
//     — drives the equipped-slot icon on the paper doll AND the
//     equipped 3D model rendered to other players' clients. Each
//     visible-item slot is two fields wide (entry + enchantment); the
//     `(index - PLAYER_VISIBLE_ITEM_1_ENTRYID) % 2u == 0` check picks
//     the entry field only.
// Default behavior with no module override is identical to returning
// rawValue unchanged.
uint32 ScriptMgr::RewriteItemFieldOnEgress(Object const* obj, uint16 index, uint32 rawValue)
{
    if (!obj)
        return rawValue;
    if (index == OBJECT_FIELD_ENTRY && obj->isType(TYPEMASK_ITEM))
    {
        OnItemBuildValuesUpdate(static_cast<Item const*>(obj), rawValue);
    }
    else if (obj->isType(TYPEMASK_PLAYER)
             && index >= PLAYER_VISIBLE_ITEM_1_ENTRYID
             && index <= PLAYER_VISIBLE_ITEM_19_ENTRYID
             && ((index - PLAYER_VISIBLE_ITEM_1_ENTRYID) % 2u) == 0)
    {
        OnItemBuildValuesUpdate(nullptr, rawValue);
    }
    return rawValue;
}

AllItemScript::AllItemScript(const char* name) :
    ScriptObject(name)
{
    ScriptRegistry<AllItemScript>::AddScript(this);
}

ItemScript::ItemScript(const char* name) :
    ScriptObject(name)
{
    ScriptRegistry<ItemScript>::AddScript(this);
}

template class AC_GAME_API ScriptRegistry<AllItemScript>;
template class AC_GAME_API ScriptRegistry<ItemScript>;
