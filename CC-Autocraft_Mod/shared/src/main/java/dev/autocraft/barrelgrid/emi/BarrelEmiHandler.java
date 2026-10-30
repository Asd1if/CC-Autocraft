package dev.autocraft.barrelgrid.emi;

import dev.autocraft.barrelgrid.BarrelGridConfig;
import dev.autocraft.barrelgrid.ClientNet;
import dev.autocraft.barrelgrid.ClientTransfer;
import dev.emi.emi.api.recipe.EmiPlayerInventory;
import dev.emi.emi.api.recipe.EmiRecipe;
import dev.emi.emi.api.recipe.VanillaEmiRecipeCategories;
import dev.emi.emi.api.recipe.handler.EmiCraftContext;
import dev.emi.emi.api.recipe.handler.EmiRecipeHandler;
import dev.emi.emi.api.stack.EmiIngredient;
import dev.emi.emi.api.stack.EmiStack;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.inventory.AbstractContainerScreen;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.inventory.Slot;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.material.Fluid;

import java.util.ArrayList;
import java.util.List;

/** Кнопка «+» EMI для рецептов верстака в хранилищах-кодировщиках из конфига. */
public class BarrelEmiHandler<T extends AbstractContainerMenu> implements EmiRecipeHandler<T> {
    @Override
    public EmiPlayerInventory getInventory(AbstractContainerScreen<T> screen) {
        List<Slot> grid = ClientTransfer.grid(screen.getMenu(), Minecraft.getInstance().player);
        if (grid == null) {
            return EmiPlayerInventory.of(Minecraft.getInstance().player);
        }
        List<EmiStack> stacks = new ArrayList<>();
        for (ItemStack stack : ClientTransfer.sources(grid, Minecraft.getInstance().player)) {
            if (!stack.isEmpty()) {
                stacks.add(EmiStack.of(stack));
            }
        }
        return new EmiPlayerInventory(stacks);
    }

    @Override
    public boolean supportsRecipe(EmiRecipe recipe) {
        return recipe.getCategory() == VanillaEmiRecipeCategories.CRAFTING && wanted(recipe) != null;
    }

    @Override
    public boolean canCraft(EmiRecipe recipe, EmiCraftContext<T> context) {
        List<List<ItemStack>> wanted = wanted(recipe);
        List<Slot> grid = ClientTransfer.grid(context.getScreenHandler(), Minecraft.getInstance().player);
        return wanted != null && grid != null && ClientNet.canSend()
                && ClientTransfer.missing(grid, Minecraft.getInstance().player, wanted).isEmpty();
    }

    @Override
    public boolean craft(EmiRecipe recipe, EmiCraftContext<T> context) {
        // Крафт «сразу в инвентарь/курсор» здесь не имеет смысла — только раскладка в сетку.
        if (context.getDestination() != EmiCraftContext.Destination.NONE) {
            return false;
        }
        List<List<ItemStack>> wanted = wanted(recipe);
        if (wanted == null || !ClientNet.canSend()
                || ClientTransfer.grid(context.getScreenHandler(), Minecraft.getInstance().player) == null) {
            return false;
        }
        ClientNet.send(ClientTransfer.fullStacks(context.getAmount() > 1 || Screen.hasShiftDown()), wanted);
        Minecraft.getInstance().setScreen(context.getScreen());
        return true;
    }

    /** Что положить в каждую из 9 ячеек; null — рецепт нельзя перенести. */
    private static List<List<ItemStack>> wanted(EmiRecipe recipe) {
        List<List<ItemStack>> inputs = new ArrayList<>();
        for (EmiIngredient ingredient : recipe.getInputs()) {
            List<EmiStack> stacks = ingredient.getEmiStacks();
            boolean fluid = stacks.stream().anyMatch(s -> s.getKey() instanceof Fluid);
            if (fluid && !BarrelGridConfig.get().ignoreFluids) {
                return null;
            }
            // Жидкости пропускаем: у них нет предмета, ячейка остаётся пустой.
            inputs.add(ClientTransfer.alternatives(stacks.stream()
                    .filter(s -> !(s.getKey() instanceof Fluid))
                    .map(EmiStack::getItemStack)));
        }
        return ClientTransfer.toGrid(inputs);
    }
}
