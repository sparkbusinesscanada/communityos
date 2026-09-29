import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchHouseholds from '@salesforce/apex/Family360Controller.searchHouseholds';
import getHousehold from '@salesforce/apex/Family360Controller.getHousehold';
import getInsights from '@salesforce/apex/Family360Controller.getInsights';
import createTask from '@salesforce/apex/Family360Controller.createTask';
import addNote from '@salesforce/apex/Family360Controller.addNote';

const SEARCH_DELAY_MS = 350;

export default class Family360 extends NavigationMixin(LightningElement) {
    @api recordId;

    searchTerm = '';
    @track hits = [];
    searching = false;
    searchedOnce = false;

    @track household;
    loadingHousehold = false;

    @track insights;
    loadingInsights = false;

    noteText = '';
    noteTeamMember = '';
    savingNote = false;

    searchTimer;

    connectedCallback() {
        if (this.recordId) {
            this.loadHousehold(this.recordId);
        }
    }

    get showBack() {
        return !this.recordId;
    }

    get hasHits() {
        return this.hits.length > 0;
    }

    get showNoResults() {
        return this.searchedOnce && !this.searching && !this.hasHits && this.searchTerm.length >= 3;
    }

    get teamMemberOptions() {
        const values = (this.household && this.household.teamMembers) || [];
        return [{ label: '— Team member —', value: '' }, ...values.map((v) => ({ label: v, value: v }))];
    }

    get sections() {
        const h = this.household;
        if (!h) {
            return [];
        }
        return [
            { key: 'people', label: `People (${h.people.length})`, rows: h.people, empty: 'No contacts on this household.' },
            { key: 'bookings', label: `Parties & bookings (${h.bookings.length})`, rows: h.bookings, empty: 'No bookings yet.' },
            { key: 'orders', label: `Square orders (${h.orders.length})`, rows: h.orders, empty: 'No orders.' },
            { key: 'camps', label: `Camps & classes (${h.camps.length})`, rows: h.camps, empty: 'No camp registrations.' },
            { key: 'notes', label: `Staff notes (${h.notes.length})`, rows: h.notes, empty: 'No staff notes yet.' }
        ].map((s) => ({ ...s, hasRows: s.rows.length > 0 }));
    }

    get hasOpenTasks() {
        return this.household && this.household.openTasks.length > 0;
    }

    get insightTasks() {
        if (!this.insights || !this.insights.suggestedTasks) {
            return [];
        }
        return this.insights.suggestedTasks.map((t, i) => ({
            ...t,
            key: `t${i}`,
            dueLabel: t.dueInDays === 0 ? 'Due today' : `Due in ${t.dueInDays} day${t.dueInDays === 1 ? '' : 's'}`
        }));
    }

    get insightList() {
        return this.insights && this.insights.insights ? this.insights.insights.map((x, i) => ({ ...x, key: `i${i}` })) : [];
    }

    get hasInsightTasks() {
        return this.insightTasks.length > 0;
    }

    get hasInsightList() {
        return this.insightList.length > 0;
    }

    get insightsButtonLabel() {
        return this.insights ? 'Refresh insights' : 'Get insights';
    }

    get noteDisabled() {
        return this.savingNote || !this.noteText.trim();
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value || '';
        window.clearTimeout(this.searchTimer);
        if (this.searchTerm.trim().length < 3) {
            this.hits = [];
            this.searchedOnce = false;
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.searchTimer = window.setTimeout(() => this.runSearch(), SEARCH_DELAY_MS);
    }

    async runSearch() {
        this.searching = true;
        try {
            this.hits = await searchHouseholds({ term: this.searchTerm.trim() });
            this.searchedOnce = true;
        } catch (e) {
            this.toast('Search failed', this.errorText(e), 'error');
        } finally {
            this.searching = false;
        }
    }

    handleSelectHit(event) {
        const id = event.currentTarget.dataset.id;
        this.hits = [];
        this.searchedOnce = false;
        this.loadHousehold(id);
    }

    handleBack() {
        this.household = undefined;
        this.insights = undefined;
    }

    async loadHousehold(accountId) {
        this.loadingHousehold = true;
        this.insights = undefined;
        try {
            this.household = await getHousehold({ accountId });
        } catch (e) {
            this.toast('Could not load household', this.errorText(e), 'error');
        } finally {
            this.loadingHousehold = false;
        }
    }

    async reloadHousehold() {
        const id = this.household.accountId;
        try {
            this.household = await getHousehold({ accountId: id });
        } catch (e) {
            this.toast('Could not refresh', this.errorText(e), 'error');
        }
    }

    async handleGetInsights() {
        this.loadingInsights = true;
        try {
            const res = await getInsights({ accountId: this.household.accountId });
            this.insights = res;
            if (!res.ok) {
                this.toast('AI response blocked', res.error, 'warning');
            }
        } catch (e) {
            this.toast('Insights failed', this.errorText(e), 'error');
        } finally {
            this.loadingInsights = false;
        }
    }

    async handleCreateTask(event) {
        const key = event.currentTarget.dataset.key;
        const t = this.insightTasks.find((x) => x.key === key);
        if (!t) {
            return;
        }
        try {
            await createTask({
                accountId: this.household.accountId,
                subject: t.subject,
                reason: t.reason,
                dueInDays: t.dueInDays,
                relatedRecordId: t.relatedRecordId,
                logId: this.insights.logId
            });
            this.removeSuggestion(key);
            this.toast('Task created', t.subject, 'success');
            await this.reloadHousehold();
        } catch (e) {
            this.toast('Could not create task', this.errorText(e), 'error');
        }
    }

    handleDismissTask(event) {
        this.removeSuggestion(event.currentTarget.dataset.key);
    }

    removeSuggestion(key) {
        const index = Number(key.substring(1));
        const next = [...this.insights.suggestedTasks];
        next.splice(index, 1);
        this.insights = { ...this.insights, suggestedTasks: next };
    }

    handleNoteInput(event) {
        this.noteText = event.target.value || '';
    }

    handleTeamMember(event) {
        this.noteTeamMember = event.detail.value;
    }

    async handleSaveNote() {
        this.savingNote = true;
        try {
            await addNote({
                accountId: this.household.accountId,
                contactId: this.household.primaryContactId,
                text: this.noteText.trim(),
                teamMember: this.noteTeamMember
            });
            this.noteText = '';
            this.toast('Note saved', 'Added to staff notes.', 'success');
            await this.reloadHousehold();
        } catch (e) {
            this.toast('Could not save note', this.errorText(e), 'error');
        } finally {
            this.savingNote = false;
        }
    }

    handleOpenRecord(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, actionName: 'view' }
        });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorText(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Unknown error';
    }
}
