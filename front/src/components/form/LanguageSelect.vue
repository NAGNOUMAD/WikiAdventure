<template>
  <q-select
    @input="onSelect($event)" name="lang" outlined hint=""
    :options="options" :label="$t('input.langSelect')" 
    :value="getLang" :display-value="getLangLabel"
    v-bind="$attrs" v-on="$listeners"
  >
  </q-select>
</template>
<script lang="ts">
import { defineComponent } from '@vue/composition-api';
import { getLabel, Lang } from 'src/i18n';

export default defineComponent({
  name: 'LangSelect',
  methods: {
    onSelect(event:any) {
      this.$store.commit('globalForm/setLang', event.value);
    }
  },
  computed: {
    options():Array<{ value:string, label:string }> {
      var optionsList:Array<{ value:string, label:string }> = [];
      for (var v in Lang) {
        var option:{ value:string, label:string } = {value: v, label: getLabel(v)};
        optionsList.push(option);
      }
      return optionsList;

    },
    getLang():string {
      return this.$store.state.globalForm.lang.toString();
    },
    getLangLabel():string {
     return getLabel(this.$store.state.globalForm.lang);
    }
  }
});
</script>