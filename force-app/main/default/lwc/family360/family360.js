import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchHouseholds from '@salesforce/apex/Family360Controller.searchHouseholds';
import getHousehold from '@salesforce/apex/Family360Controller.getHousehold';
import getInsights from '@salesforce/apex/Family360Controller.getInsights';
import createTask from '@salesforce/apex/Family360Controller.createTask';
import addNote from '@salesforce/apex/Family360Controller.addNote';
import getDeskQuestions from '@salesforce/apex/Family360Controller.getDeskQuestions';
import askDesk from '@salesforce/apex/Family360Controller.askDesk';
import markDeskOutcome from '@salesforce/apex/Family360Controller.markDeskOutcome';

const SEARCH_DELAY_MS = 350;
const STATUS_CLASS = {
    Answered: 'badge badge-good',
    'Not in records': 'badge badge-quiet',
    Blocked: 'badge badge-bad',
    Resolved: 'badge badge-good',
    Escalated: 'badge badge-warn'
};

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

    @track deskQuestions = [];
    selectedKeys = [];
    @track deskAnswers = [];
    asking = false;
    deskError;

    noteText = '';
    noteTeamMember = '';
    savingNote = false;

    searchTimer;

    @wire(getDeskQuestions)
    wiredQuestions({ data }) {
        if (data) {
            this.deskQuestions = data;
        }
    }

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

    get initials() {
        const n = (this.household && this.household.name) || '';
        return n.split(/\s+/).filter((w) => /[A-Za-z]/.test(w)).slice(0, 2).map((w) => w[0].toUpperCase()).join('') || '#';
    }

    get heroSub() {
        const h = this.household;
        return [h.phone, h.customerSince ? `Customer since ${h.customerSince}` : null].filter(Boolean).join(' · ');
    }

    get stats() {
        const h = this.household;
        if (!h) {
            return [];
        }
        const money = new Intl.NumberFormat('en-CA', { style: 'currency', currency: 'CAD', maximumFractionDigits: 0 });
        return [
            { key: 'bookings', value: h.bookingCount || 0, label: 'Bookings' },
            { key: 'parties', value: h.partiesHosted || 0, label: 'Parties hosted' },
            { key: 'spend', value: money.format(h.lifetimeSpend || 0), label: 'Paid on Square' },
            { key: 'unpaid', value: h.unpaidOrders || 0, label: 'Unpaid orders', alert: (h.unpaidOrders || 0) > 0 },
            { key: 'next', value: h.nextEvent || '—', label: 'Next event' },
            { key: 'last', value: h.lastEvent || '—', label: 'Last event' }
        ].map((s) => ({ ...s, cls: s.alert ? 'stat stat-alert' : 'stat' }));
    }

    get people() {
        return this.household ? this.household.people : [];
    }

    get hasPeople() {
        return this.people.length > 0;
    }

    get historyTabs() {
        const h = this.household;
        if (!h) {
            return [];
        }
        return [
            { key: 'bookings', label: `Parties (${h.bookings.length})`, rows: h.bookings, empty: 'No bookings yet.' },
            { key: 'orders', label: `Orders (${h.orders.length})`, rows: h.orders, empty: 'No Square orders.' },
            { key: 'notes', label: `Notes (${h.notes.length})`, rows: h.notes, empty: 'No staff notes yet.' },
            { key: 'camps', label: `Camps (${h.camps.length})`, rows: h.camps, empty: 'No camp registrations.' }
        ].map((t) => ({ ...t, hasRows: t.rows.length > 0 }));
    }

    get questionOptions() {
        return this.deskQuestions.map((q) => ({ label: q.question, value: q.key }));
    }

    get askLabel() {
        const n = this.selectedKeys.length;
        return n === 0 ? 'Ask' : `Ask ${n} question${n === 1 ? '' : 's'}`;
    }

    get askDisabled() {
        return this.asking || this.selectedKeys.length === 0;
    }

    get answerCards() {
        return this.deskAnswers.map((a) => ({
            ...a,
            badgeClass: STATUS_CLASS[a.outcome || a.status] || 'badge badge-quiet',
            badgeText: a.outcome || a.status,
            hasLinks: a.sourceLinks && a.sourceLinks.length > 0,
            canMark: !a.outcome && a.status !== 'Blocked'
        }));
    }

    get hasAnswers() {
        return this.deskAnswers.length > 0;
    }

    get deskHistory() {
        const rows = (this.household && this.household.deskHistory) || [];
        return rows.map((r) => ({ ...r, badgeClass: STATUS_CLASS[r.badge] || 'badge badge-quiet' }));
    }

    get hasDeskHistory() {
        return this.deskHistory.length > 0;
    }

    get teamMemberOptions() {
        const values = (this.household && this.household.teamMembers) || [];
        return [{ label: '— Team member —', value: '' }, ...values.map((v) => ({ label: v, value: v }))];
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
        return this.insights ? 'Refresh' : 'Get insights';
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
        this.deskAnswers = [];
        this.selectedKeys = [];
    }

    async loadHousehold(accountId) {
        this.loadingHousehold = true;
        this.insights = undefined;
        this.deskAnswers = [];
        this.selectedKeys = [];
        try {
            this.household = await getHousehold({ accountId });
        } catch (e) {
            this.toast('Could not load household', this.errorText(e), 'error');
        } finally {
            this.loadingHousehold = false;
        }
    }

    async reloadHousehold() {
        try {
            this.household = await getHousehold({ accountId: this.household.accountId });
        } catch (e) {
            this.toast('Could not refresh', this.errorText(e), 'error');
        }
    }

    handleQuestionChange(event) {
        this.selectedKeys = event.detail.value;
    }

    handleSelectAll() {
        this.selectedKeys = this.deskQuestions.map((q) => q.key);
    }

    handleClearQuestions() {
        this.selectedKeys = [];
    }

    async handleAsk() {
        this.asking = true;
        this.deskError = undefined;
        try {
            const res = await askDesk({ accountId: this.household.accountId, keys: this.selectedKeys });
            if (!res.ok) {
                this.deskError = res.error;
                this.deskAnswers = [];
            } else {
                this.deskAnswers = res.answers.map((a) => ({ ...a, outcome: null }));
                this.selectedKeys = [];
                await this.reloadHousehold();
            }
        } catch (e) {
            this.deskError = this.errorText(e);
        } finally {
            this.asking = false;
        }
    }

    async handleOutcome(event) {
        const id = event.currentTarget.dataset.id;
        const outcome = event.currentTarget.dataset.outcome;
        try {
            await markDeskOutcome({ deskQuestionId: id, outcome });
            this.deskAnswers = this.deskAnswers.map((a) =>
                a.deskQuestionId === id ? { ...a, outcome: outcome === 'resolved' ? 'Resolved' : 'Escalated' } : a
            );
            await this.reloadHousehold();
        } catch (e) {
            this.toast('Could not save', this.errorText(e), 'error');
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
        event.stopPropagation();
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
