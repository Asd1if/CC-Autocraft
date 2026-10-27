package dev.autocraft.barrelgrid.jei;

import dev.autocraft.barrelgrid.BarrelGrid;
import dev.autocraft.barrelgrid.Compat;
import dev.autocraft.barrelgrid.MenuProbe;
import mezz.jei.api.IModPlugin;
import mezz.jei.api.JeiPlugin;
import mezz.jei.api.constants.RecipeTypes;
import mezz.jei.api.registration.IRecipeTransferRegistration;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.inventory.MenuType;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Fabric находит плагин через entrypoint "jei_mod_plugin", Forge/NeoForge — по аннотации. */
@JeiPlugin
public class BarrelJeiPlugin implements IModPlugin {
    @Override
    public ResourceLocation getPluginUid() {
        return Compat.id(BarrelGrid.MOD_ID, "jei");
    }

    @Override
    @SuppressWarnings({"unchecked", "rawtypes"})
    public void registerRecipeTransferHandlers(IRecipeTransferRegistration registration) {
        // JEI хранит один обработчик на класс меню (повторная регистрация молча заменяет прежнюю),
        // поэтому группируем типы по классу.
        Map<Class<? extends AbstractContainerMenu>, List<MenuType<?>>> byClass = new LinkedHashMap<>();
        MenuProbe.storageMenus().forEach((type, menuClass) ->
                byClass.computeIfAbsent(menuClass, c -> new ArrayList<>()).add(type));

        byClass.forEach((menuClass, types) -> {
            // Один тип — JEI сверит его сам; несколько — проверка только по слотам и конфигу.
            MenuType type = types.size() == 1 ? types.get(0) : null;
            registration.addRecipeTransferHandler(
                    new BarrelJeiHandler(registration.getTransferHelper(), RecipeTypes.CRAFTING, menuClass, type),
                    RecipeTypes.CRAFTING);
        });
    }
}
