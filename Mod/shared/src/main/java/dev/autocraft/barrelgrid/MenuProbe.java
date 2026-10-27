package dev.autocraft.barrelgrid;

import com.mojang.logging.LogUtils;
import net.minecraft.client.Minecraft;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.inventory.MenuType;
import net.minecraft.world.inventory.Slot;
import org.slf4j.Logger;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Клиент: какие типы меню — хранилища на 27 слотов. Тип меню не говорит ни о размере, ни о классе,
 * поэтому создаём пробный экземпляр (без мира и блока) и считаем его слоты. Это же отсекает верстак
 * и прочие окна, чтобы не перехватить у них кнопку JEI/EMI.
 */
public final class MenuProbe {
    private static final Logger LOGGER = LogUtils.getLogger();

    private MenuProbe() {
    }

    /** Подходящие типы меню из конфига ("*" — все) → класс меню (JEI ищет обработчик по классу). */
    public static Map<MenuType<?>, Class<? extends AbstractContainerMenu>> storageMenus() {
        List<String> menus = BarrelGridConfig.get().menus;
        boolean all = menus.contains("*");
        for (String entry : menus) {
            ResourceLocation id = ResourceLocation.tryParse(entry);
            if (!entry.equals("*") && (id == null || !BuiltInRegistries.MENU.containsKey(id))) {
                LOGGER.warn("barrelgrid: unknown menu type '{}' in config", entry);
            }
        }

        Map<MenuType<?>, Class<? extends AbstractContainerMenu>> out = new LinkedHashMap<>();
        for (MenuType<?> type : BuiltInRegistries.MENU) {
            ResourceLocation id = BuiltInRegistries.MENU.getKey(type);
            if (!all && !BarrelGrid.matchesAny(menus, id)) {
                continue;
            }
            AbstractContainerMenu probe;
            try {
                probe = type.create(0, new Inventory(Minecraft.getInstance().player));
            } catch (Throwable e) {
                // Модовые меню с особым конструктором (ждут данные от сервера) так не создать.
                if (all) {
                    LOGGER.debug("barrelgrid: cannot probe menu {}", id, e);
                } else {
                    LOGGER.warn("barrelgrid: cannot probe menu {}, button disabled for it", id, e);
                }
                continue;
            }
            int storageSlots = 0;
            for (Slot slot : probe.slots) {
                if (!(slot.container instanceof Inventory)) {
                    storageSlots++;
                }
            }
            if (storageSlots == BarrelGrid.STORAGE_SLOTS) {
                out.put(type, probe.getClass());
            } else if (!all) {
                LOGGER.warn("barrelgrid: menu {} has {} storage slots, not {}", id, storageSlots,
                        BarrelGrid.STORAGE_SLOTS);
            }
        }
        LOGGER.info("barrelgrid: transfer button enabled for {} menu type(s): {}", out.size(),
                out.keySet().stream().map(BuiltInRegistries.MENU::getKey).toList());
        return out;
    }
}
