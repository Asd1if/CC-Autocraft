package dev.autocraft.barrelgrid.jei;

import dev.autocraft.barrelgrid.BarrelGridConfig;
import dev.autocraft.barrelgrid.ClientNet;
import dev.autocraft.barrelgrid.ClientTransfer;
import mezz.jei.api.constants.VanillaTypes;
import mezz.jei.api.gui.ingredient.IRecipeSlotView;
import mezz.jei.api.gui.ingredient.IRecipeSlotsView;
import mezz.jei.api.recipe.RecipeIngredientRole;
import mezz.jei.api.recipe.RecipeType;
import mezz.jei.api.recipe.transfer.IRecipeTransferError;
import mezz.jei.api.recipe.transfer.IRecipeTransferHandler;
import mezz.jei.api.recipe.transfer.IRecipeTransferHandlerHelper;
import net.minecraft.network.chat.Component;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.inventory.MenuType;
import net.minecraft.world.inventory.Slot;
import net.minecraft.world.item.ItemStack;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * Кнопка «+» JEI для рецептов верстака в хранилище-кодировщике.
 * JEI ищет обработчик по точному классу меню, поэтому на каждый класс меню — свой экземпляр;
 * menuType == null, если этот класс используют несколько типов меню.
 * R — тип рецепта (CraftingRecipe в 1.20.1, RecipeHolder&lt;CraftingRecipe&gt; в 1.21.1).
 */
public class BarrelJeiHandler<C extends AbstractContainerMenu, R> implements IRecipeTransferHandler<C, R> {
    private final IRecipeTransferHandlerHelper helper;
    private final RecipeType<R> recipeType;
    private final Class<? extends C> menuClass;
    private final MenuType<C> menuType;

    public BarrelJeiHandler(IRecipeTransferHandlerHelper helper, RecipeType<R> recipeType,
                            Class<? extends C> menuClass, MenuType<C> menuType) {
        this.helper = helper;
        this.recipeType = recipeType;
        this.menuClass = menuClass;
        this.menuType = menuType;
    }

    @Override
    public Class<? extends C> getContainerClass() {
        return menuClass;
    }

    @Override
    public Optional<MenuType<C>> getMenuType() {
        return Optional.ofNullable(menuType);
    }

    @Override
    public RecipeType<R> getRecipeType() {
        return recipeType;
    }

    // В новых JEI 1.20.1 метод помечен устаревшим, но новый вариант по умолчанию вызывает его же,
    // так что эта перегрузка работает со всеми версиями JEI 15.x и 19.x.
    @SuppressWarnings("removal")
    @Override
    public IRecipeTransferError transferRecipe(C menu, R recipe, IRecipeSlotsView slots, Player player,
                                               boolean maxTransfer, boolean doTransfer) {
        List<Slot> grid = ClientTransfer.grid(menu, player);
        if (grid == null) {
            return helper.createUserErrorWithTooltip(Component.translatable("barrelgrid.message.not_storage"));
        }
        if (!ClientNet.canSend()) {
            return helper.createUserErrorWithTooltip(Component.translatable("barrelgrid.message.no_server"));
        }
        List<IRecipeSlotView> views = slots.getSlotViews(RecipeIngredientRole.INPUT);
        List<List<ItemStack>> inputs = new ArrayList<>();
        for (IRecipeSlotView view : views) {
            boolean fluid = view.getAllIngredients().anyMatch(i -> i.getType() != VanillaTypes.ITEM_STACK);
            if (fluid && !BarrelGridConfig.get().ignoreFluids) {
                return helper.createUserErrorWithTooltip(Component.translatable("barrelgrid.message.fluid"));
            }
            // Жидкости (и прочие не-предметы) пропускаем: getItemStacks отдаёт только предметы.
            inputs.add(ClientTransfer.alternatives(view.getItemStacks()));
        }
        List<List<ItemStack>> wanted = ClientTransfer.toGrid(inputs);
        if (wanted == null) {
            return helper.createInternalError();
        }

        List<Integer> missing = ClientTransfer.missing(grid, player, wanted);
        if (!missing.isEmpty()) {
            List<IRecipeSlotView> missingViews = new ArrayList<>();
            for (int index : missing) {
                missingViews.add(views.get(index));
            }
            return helper.createUserErrorForMissingSlots(
                    Component.translatable("barrelgrid.message.missing"), missingViews);
        }

        if (doTransfer) {
            ClientNet.send(ClientTransfer.fullStacks(maxTransfer), wanted);
        }
        return null;
    }
}
